#!/bin/bash
# rollingWRT build - three self-contained stages, split so each fits GitHub's 6h limit
# and nothing compiles twice.
#
# rollingWRT is a ROLLING distribution riding OpenWrt's latest snapshot. The device
# pulls its whole base userland (busybox, libc, base packages, cryptsetup, ...) from
# OpenWrt's own apk feeds via `apk upgrade`. We build and host ONLY two things:
#   1. a custom kernel + every kmod - stock OpenWrt disables KVM_IOAPIC (a hypervisor
#      needs the in-kernel irqchip) and cannot add the Intel Xe DRM stack
#      (kmod-drm-xe/gpuvm/gpusvm) out-of-tree, so a custom kernel is genuinely required;
#   2. our add-on packages (incus, qemu, mesa, zfs, tpm2, sbctl, systemd-boot, the
#      on-device boot tooling, luci apps).
#
# STAGE=kernel : build ONLY the kernel + every kmod + the kernel-as-apk, against a
#                prebuilt EXTERNAL_TOOLCHAIN (OpenWrt's own openwrt-toolchain download)
#                so no cross-toolchain is ever compiled. Publishes the bucketed kmods
#                feeds + the kernel / rollingwrt-kernel apks. Host tools are built from
#                source once (cacheable); nothing else in the tree is built.
# STAGE=pkg    : build the add-on packages in PKG_DIRS against OpenWrt's OFFICIAL
#                downloaded SDK (SDK_IN) for the SAME snapshot, as normal apks. Packages
#                that build-depend on each other (mesa -> virglrenderer -> qemu) go in
#                ONE pkg job and share the live staging_dir, exactly like OpenWrt's
#                phase2 buildbot - so nothing is compiled twice and no staging is handed
#                between jobs. zfs builds its kmod-fs-zfs against the SDK's stock kernel;
#                that kernel is the same snapshot version as ours and our extra config
#                (KVM_IOAPIC, Xe) does not change the kmod vermagic, so it loads on our
#                kernel.
# STAGE=index  : collect every stage's apks (from OUT/collect) into one signed apk feed.
#
# env (common):
#   STAGE      kernel | pkg | index         PIN   snapshot commit
#   JOBS       parallelism (default nproc)   OUT   artifact dir (default $PWD/out)
#   FEED       our feed dir                  OVERLAY  our overlay dir
#   APK_SIGNING_KEY  PEM private key (feed + package signing); ephemeral if unset
# env (kernel stage):
#   OWRT       openwrt source tree to build in (cloned at PIN if absent)
#   TC_ROOT    prebuilt external toolchain root (the extracted openwrt-toolchain), e.g.
#              .../toolchain-x86_64_gcc-14.4.0_musl. Its info.mk seeds the target
#              runtime-toolchain package's version (external builds skip the gcc compile
#              that would otherwise fill it, leaving GCC_VERSION=unknown -> apk rejects it).
#   GCC_VER    external toolchain gcc version (default read from TC_ROOT/info.mk)
# env (pkg stage):
#   OWRT       where to extract the SDK (a fixed canonical path so the extracted
#              staging's absolute paths stay valid within the job)
#   SDK_IN     the OFFICIAL OpenWrt SDK tarball to build against
#   PKG_DIRS   package source dirs to compile, e.g. "feeds/video/mesa"
#   SELECT     which package variants/flags to enable (see below)
#   EXTRA_FEEDS   extra src-git feeds to add, "name=url" (e.g. video=https://...)
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"      # repo/
STAGE="${STAGE:-kernel}"
JOBS="${JOBS:-$(nproc)}"
OUT="${OUT:-$PWD/out}"
FEED="${FEED:-$HERE/feed}"
OVERLAY="${OVERLAY:-$HERE/overlay}"
REPO_SLUG="${REPO_SLUG:-cmspam/rollingwrt}"
FEED_BASE="https://github.com/$REPO_SLUG/releases/download"
# kmods split across this many releases (GitHub caps a release at 1000 assets). FIXED
# for URL stability: customfeeds.list is baked into the rootfs and not regenerated.
KMOD_BUCKETS="${KMOD_BUCKETS:-3}"
OPENWRT_GIT="${OPENWRT_GIT:-https://github.com/openwrt/openwrt.git}"

mkdir -p "$OUT"

# Provide our OWN fixed signing key so one key signs every package AND the feed index,
# and the rootfs trusts exactly it. We write public-key.pem ourselves so the buildroot's
# `openssl ec -pubout` rule does not run (lets the secret be RSA or EC). Without the
# secret an ephemeral key is used (dev build).
install_signing_key() { # $1=buildroot dir
	[ -n "${APK_SIGNING_KEY:-}" ] || return 0
	printf '%s' "$APK_SIGNING_KEY" > "$1/private-key.pem"
	openssl pkey -in "$1/private-key.pem" -pubout -out "$1/public-key.pem"
}

sign_feed() { # $1=buildroot(for apk+keys) $2=dir-of-apks -> build+sign packages.adb
	local apk="$1/staging_dir/host/bin/apk" sign=()
	[ -f "$1/private-key.pem" ] && sign=(--sign-key "$1/private-key.pem")
	( cd "$2" && ls ./*.apk >/dev/null 2>&1 && "$apk" mkndx --keys-dir "$1" "${sign[@]}" -o packages.adb ./*.apk )
}

# Our add-on apks land under bin/packages/x86_64/rollingwrt and our luci-app-* under
# .../luci. We deliberately do NOT collect the 'video' feed: the only video-feed package a
# job builds is libmesa-softpipe, a build-time transient for qemu/virglrenderer linkage -
# OpenWrt publishes every mesa variant we ship, so the device pulls mesa from its video
# feed and we never host it. $3 non-empty keeps kmods (a package stage builds ONLY our
# packages, so any kmod it made - e.g. zfs's kmod-fs-zfs - is ours and belongs in the
# feed); empty drops them (the kernel stage's kernel + all kmods go to the kmods feeds).
collect_apks() { # $1=buildroot $2=dest $3=keep_kmods
	mkdir -p "$2"
	local d
	for d in rollingwrt; do
		[ -d "$1/bin/packages/x86_64/$d" ] || continue
		find "$1/bin/packages/x86_64/$d" -name '*.apk' -exec cp -f {} "$2/" \;
	done
	for d in "$FEED"/luci-app-*; do
		[ -d "$d" ] || continue
		find "$1/bin/packages/x86_64/luci" -name "$(basename "$d")-*.apk" -exec cp -f {} "$2/" \; 2>/dev/null || true
	done
	if [ -n "${3:-}" ]; then
		# our kmods (kmod-fs-zfs) can land under bin/targets too; pull them in.
		find "$1/bin/targets" -name 'kmod-*.apk' -exec cp -f {} "$2/" \; 2>/dev/null || true
	else
		find "$2" \( -name 'kmod-*.apk' -o -name 'kernel-*.apk' -o -name 'rollingwrt-kernel-*.apk' \) -delete 2>/dev/null || true
	fi
}

# Generate the incus-vm metapackage apk directly, WITHOUT OpenWrt building its DEPENDS.
# OpenWrt compiles a package's declared DEPENDS as prerequisites, so building incus-vm the
# normal way compiles kmod-kvm/vhost/tun against whatever kernel the job has - the SDK's
# stock kernel in a pkg job, which is wrong. incus-vm ships only a marker file; read its
# name/version/DEPENDS from the Makefile and mkpkg it here so nothing is compiled. The
# DEPENDS resolve on-device from our feeds (incus, qemu, and the kmods from the kmods feed).
gen_incus_vm() { # $1=buildroot(apk+key) $2=dest-dir
	local mk="$FEED/incus-vm/Makefile" apk="$1/staging_dir/host/bin/apk"
	[ -f "$mk" ] && [ -x "$apk" ] || return 0
	local ver rel deps files sign=()
	ver="$(sed -n 's/^PKG_VERSION:=//p' "$mk" | head -1)"
	rel="$(sed -n 's/^PKG_RELEASE:=//p' "$mk" | head -1)"
	deps="$(sed -n '/DEPENDS:=/,/[^\\]$/p' "$mk" | grep -oE '\+[a-zA-Z0-9_-]+' | tr -d '+' | tr '\n' ' ')"
	[ -n "$ver" ] || return 0
	files="$(mktemp -d)"; mkdir -p "$files/usr/lib/incus"; echo vm > "$files/usr/lib/incus/vm-support"
	[ -f "$1/private-key.pem" ] && sign=(--sign "$1/private-key.pem")
	"$apk" mkpkg --info "name:incus-vm" --info "version:$ver-r${rel:-1}" --info "arch:x86_64" \
		--info "description:Incus virtual-machine support (qemu + OVMF + KVM/vhost kmods)" \
		--info "license:Apache-2.0" --info "depends:$deps" \
		--files "$files" "${sign[@]}" --output "$2/incus-vm-$ver-r${rel:-1}.apk"
	rm -rf "$files"
}

# git clone with retry: openwrt.git is large and a shared-runner clone occasionally dies
# mid-transfer ("RPC failed; curl 56 ... TLS packet", exit 128), which is transient.
git_clone() { # $1=url $2=dest
	local i
	for i in 1 2 3 4 5; do
		git clone -q "$1" "$2" && return 0
		echo "git clone $1 failed (attempt $i); retrying" >&2
		rm -rf "$2"; sleep 15
	done
	echo "ERROR: git clone $1 failed after retries" >&2; return 1
}

# clone openwrt at the pin + apply our overlay (config-completion patches, our in-tree
# KernelPackages, KVM_IOAPIC, branding). Shared by the kernel stage.
prepare_tree() { # $1=tree dir $2=pin
	local owrt="$1" pin="$2"
	if [ ! -d "$owrt/.git" ]; then git_clone "$OPENWRT_GIT" "$owrt"; fi
	git -C "$owrt" fetch --quiet origin "$pin" 2>/dev/null || git -C "$owrt" fetch --quiet origin main
	git -C "$owrt" checkout -q -f -B rollingwrt "$pin"
	git -C "$owrt" reset -q --hard "$pin"
	local p kc
	for p in "$OVERLAY"/patches/*.patch; do git -C "$owrt" apply "$p"; done
	cp "$OVERLAY"/modules/*.mk "$owrt/package/kernel/linux/modules/"
	# The kernel apk (and the kmods' dep on it) versions the kernel as
	# <version>~<hex-vermagic>-r<rel>. We host the feed on GitHub Releases, which rewrites
	# ~ to . in asset filenames, so that one apk becomes undownloadable. apk allows a
	# numeric suffix after a . (but not the hex after ~), and GitHub keeps . verbatim, so
	# represent the vermagic as its cksum decimal after a . instead. Applied to the kernel
	# package version and the kmod EXTRA_DEPENDS together so they stay consistent.
	echo "LINUX_VERMAGIC_DEC = \$(shell printf '%s' '\$(LINUX_VERMAGIC)' | cksum | cut -d' ' -f1)" >> "$owrt/include/kernel.mk"
	# 1. Kernel apk + the kmods' dep on it: ~<hex-vermagic> -> .<cksum-decimal>. GitHub
	#    Releases rewrites ~ to . in asset filenames, so the ~-versioned kernel apk is
	#    otherwise unhostable; apk accepts .<digits> and GitHub keeps it verbatim.
	sed -i 's/~$(LINUX_VERMAGIC)/.$(LINUX_VERMAGIC_DEC)/g' "$owrt/include/kernel.mk" "$owrt/package/kernel/linux/Makefile"
	# 2. Give each kmod's OWN version the same .decimal. The device pulls its userland from
	#    OpenWrt's feeds, which also carry OpenWrt's kernel + identically-named kmods (built
	#    against the stock config, wrong vermagic for our kernel). OpenWrt versions those
	#    6.18.38-r1; ours become 6.18.38.<dec>-r1, which apk sorts higher, so the device
	#    installs OUR kernel and OUR kmods and never OpenWrt's. (Both also avoid the ~.)
	sed -i 's#$(subst -rc,_rc,$(LINUX_VERSION))$(if $(PKG_VERSION)#$(subst -rc,_rc,$(LINUX_VERSION)).$(LINUX_VERMAGIC_DEC)$(if $(PKG_VERSION)#' "$owrt/include/kernel.mk"
	for kc in "$owrt"/target/linux/x86/config-*; do
		grep -q '^CONFIG_KVM_IOAPIC=y' "$kc" || echo 'CONFIG_KVM_IOAPIC=y' >> "$kc"
	done
	cp "$OVERLAY/branding/banner" "$owrt/package/base-files/files/etc/banner"
	sed -i 's/^ID="%d"/ID="openwrt"/' "$owrt/package/base-files/files/usr/lib/os-release"
}

# ---------------------------------------------------------------- STAGE=kernel
if [ "$STAGE" = kernel ]; then
	PIN="${PIN:?set PIN for the kernel stage}"
	OWRT="${OWRT:-$PWD/openwrt}"
	TC_ROOT="${TC_ROOT:?set TC_ROOT: the extracted openwrt-toolchain dir}"
	echo ">>> kernel @ snapshot $PIN (external toolchain $TC_ROOT)"

	prepare_tree "$OWRT" "$PIN"
	cd "$OWRT"

	# Our feed, but with rollingwrt-kernel's DEPENDS stripped: it packages the built
	# bzImage and nothing else, yet its runtime dep (+rollingwrt-boot) would drag the
	# whole boot userland (grub, cryptsetup, tpm2, ...) into this lean kernel job. That
	# tooling is built canonically by the pkg stage; rollingwrt-boot is installed on the
	# device by the assembler's package list, and its /boot + /lib/modules apk trigger
	# fires regardless, so dropping the metadata dep here changes nothing on-device.
	RWRT_FEED="$OWRT/.rwrt-feed"
	rm -rf "$RWRT_FEED"; cp -r "$FEED" "$RWRT_FEED"
	sed -i '/DEPENDS:=+rollingwrt-boot/d' "$RWRT_FEED/rollingwrt-kernel/Makefile"

	# feeds: our (dep-stripped) feed + the stock feeds (kmod definitions live in-tree;
	# feeds install -a keeps defconfig from dropping selected packages). gensio has a
	# recursive kconfig dep that aborts defconfig, and we do not build it, so drop it.
	cp -f feeds.conf.default feeds.conf
	sed -i '/^src-git video /d' feeds.conf
	rm -rf feeds/video feeds/video.* package/feeds/video
	grep -q "src-link rollingwrt " feeds.conf || sed -i "1i src-link rollingwrt $RWRT_FEED" feeds.conf
	for attempt in 1 2 3; do
		./scripts/feeds update -a >/dev/null 2>&1 && break
		[ "$attempt" = 3 ] && { echo "ERROR: feeds update failed"; exit 1; }
		sleep 10
	done
	./scripts/feeds install -a >/dev/null 2>&1
	for broken in gensio; do ./scripts/feeds uninstall "$broken" >/dev/null 2>&1 || true; done

	# config: our kmod selections + the EXTERNAL_TOOLCHAIN pointing at the download.
	rm -rf tmp 2>/dev/null || true
	cp "$HERE/config/x86-64.config" .config
	GCC_VER="${GCC_VER:-$(sed -n 's/^GCC_VERSION=//p' "$TC_ROOT/info.mk")}"
	cat >> .config <<-CFG
		CONFIG_DEVEL=y
		CONFIG_EXTERNAL_TOOLCHAIN=y
		CONFIG_TOOLCHAIN_ROOT="$TC_ROOT"
		CONFIG_TOOLCHAIN_PREFIX="x86_64-openwrt-linux-"
		CONFIG_EXTERNAL_TOOLCHAIN_LIBC_USE_MUSL=y
		CONFIG_EXTERNAL_GCC_VERSION="$GCC_VER"
	CFG
	make defconfig >/dev/null 2>&1
	install_signing_key "$OWRT"

	# Seed the target runtime-toolchain version. An external-toolchain build never
	# compiles gcc, so the sed that fills toolchain info.mk (GCC_VERSION=<n>) never runs
	# and the placeholder GCC_VERSION=unknown survives - which makes `apk mkpkg` reject
	# libgcc/libc/... ("package version is invalid"). Copy the real info.mk from the
	# download; the make guard (grep GCC_VERSION || install placeholder) then keeps ours.
	TCD="$(make --no-print-directory val.TOOLCHAIN_DIR 2>/dev/null | tail -1)"
	mkdir -p "$TCD/stamp" "$TCD/lib" "$TCD/usr/include" "$TCD/usr/lib"
	# the info.mk make-rule also creates these; recreate them here so pre-seeding a
	# newer info.mk (which makes make skip that rule) does not leave them missing.
	ln -nsf lib "$TCD/lib64"; ln -nsf lib "$TCD/lib32"
	cp -f "$TC_ROOT/info.mk" "$TCD/info.mk"; touch "$TCD/info.mk"

	# build host tools from source (the toolchain download has none), then ONLY the
	# kernel + every kmod. package/kernel/linux/compile pulls package/libs/toolchain
	# (the target libc/libgcc runtime apks) - hence the info.mk seed above.
	make -j"$JOBS" tools/install
	make -j"$JOBS" target/linux/compile package/kernel/linux/compile
	# the kernel-as-apk (packages the built bzImage; deps stripped, so standalone).
	make -j"$JOBS" package/rollingwrt-kernel/compile

	# kmod-fs-zfs is an out-of-tree module and MUST be built against OUR kernel, never the
	# SDK's stock kernel: our config differs from upstream's (KVM_IOAPIC, the Xe DRM stack,
	# the full ALL_KMODS set), so a kmod built elsewhere is loadable only by coincidence of
	# matching vermagic and would fail silently the moment that breaks (e.g. MODVERSIONS
	# enabled upstream). Build ONLY the module here (ZFS_WITH_CONFIG=kernel, no userspace,
	# so no openssl/libudev pulled in); the zfs userland is built separately in the zfs pkg
	# job. Our config carries zfs=m for the device's package set, so select the kmod and
	# drop the userland just for this build. kmod-fs-zfs then joins the kmods feed.
	sed -i 's/^CONFIG_PACKAGE_zfs=.*/# CONFIG_PACKAGE_zfs is not set/' .config
	grep -q '^CONFIG_PACKAGE_kmod-fs-zfs=m' .config || echo 'CONFIG_PACKAGE_kmod-fs-zfs=m' >> .config
	make defconfig >/dev/null 2>&1
	ZFS_WITH_CONFIG=kernel make -j"$JOBS" package/feeds/rollingwrt/zfs/compile

	# publish: bucketed kmods (incl. kmod-fs-zfs) + the kernel and rollingwrt-kernel apks
	# (deterministic bucket per filename hash so a module keeps its release), + the pubkey.
	cp -f "$OWRT/public-key.pem" "$OUT/public-key.pem" 2>/dev/null || true
	for b in $(seq 1 "$KMOD_BUCKETS"); do mkdir -p "$OUT/kmods-$b"; done
	while IFS= read -r apk; do
		b=$(( ( $(printf '%s' "$(basename "$apk")" | cksum | cut -d' ' -f1) % KMOD_BUCKETS ) + 1 ))
		cp "$apk" "$OUT/kmods-$b/"
	done < <(find bin/targets bin/packages/x86_64 \( -name 'kmod-*.apk' -o -name 'kernel-*.apk' -o -name 'rollingwrt-kernel-*.apk' \))
	for b in $(seq 1 "$KMOD_BUCKETS"); do sign_feed "$OWRT" "$OUT/kmods-$b"; done
	echo ">>> done kernel: kmods+kernel apks=$(ls "$OUT"/kmods-*/*.apk 2>/dev/null | wc -l)"
	exit 0
fi

# ------------------------------------------------------------------ STAGE=pkg
if [ "$STAGE" = pkg ]; then
	OWRT="${OWRT:?set OWRT: the fixed path to extract the SDK into}"
	SDK_IN="${SDK_IN:?set SDK_IN: the official OpenWrt SDK tarball to build against}"
	SELECT="${SELECT:?set SELECT: packages/config to enable}"
	PKG_DIRS="${PKG_DIRS:?set PKG_DIRS: package source dirs to compile, e.g. feeds/video/mesa}"
	echo ">>> pkg [$PKG_DIRS] on SDK $(basename "$SDK_IN")"

	# Extract the SDK to the fixed canonical path. Because every stage uses the SAME
	# path, a warm SDK (staging already populated by an upstream package) needs no
	# relocation, so its build stamps stay valid and nothing gets rebuilt.
	rm -rf "$OWRT"; mkdir -p "$OWRT"
	tar -C "$OWRT" --strip-components=1 -xf "$SDK_IN"
	cd "$OWRT"

	# The SDK ships feeds.conf.default and no .config. Seed feeds.conf with our feed +
	# any extra feeds (e.g. video for mesa), then symlink every feed package in (metadata
	# only); .config picks what actually builds.
	cp -f feeds.conf.default feeds.conf
	# The SDK's 'base' feed provides the CORE openwrt packages (libxml2 and every base lib
	# a package may build-depend on - e.g. wayland's host build needs libxml2/host). It is
	# baked with the local build branch as its ref, and OpenWrt feeds can only git-clone a
	# branch/tag, never a commit. So clone openwrt at the pinned commit ourselves and point
	# the base feed at it via src-link - exact and reproducible. The base packages are NOT
	# otherwise present in the SDK.
	PIN="${PIN:?set PIN for the pkg stage (pins the base feed)}"
	BASE_SRC="$(dirname "$OWRT")/base-src"
	[ -d "$BASE_SRC/.git" ] || git_clone "$OPENWRT_GIT" "$BASE_SRC"
	git -C "$BASE_SRC" fetch -q origin "$PIN" 2>/dev/null || true
	git -C "$BASE_SRC" checkout -q -f "$PIN"
	sed -i '/root=package base/d' feeds.conf
	sed -i "1i src-link base $BASE_SRC/package" feeds.conf
	grep -q "src-link rollingwrt " feeds.conf || sed -i "1i src-link rollingwrt $FEED" feeds.conf
	if [ -n "${EXTRA_FEEDS:-}" ]; then
		for f in $EXTRA_FEEDS; do
			name="${f%%=*}"; url="${f#*=}"
			grep -q "src-git $name " feeds.conf || echo "src-git $name $url" >> feeds.conf
		done
	fi
	for attempt in 1 2 3; do
		./scripts/feeds update -a >/dev/null 2>&1 && break
		[ "$attempt" = 3 ] && { echo "ERROR: feeds update failed"; exit 1; }
		sleep 10
	done
	# Install every feed package (metadata only). We need -a, not a selective install:
	# a package's HOST_BUILD_DEPENDS (e.g. wayland needs libxml2/host to build) are not
	# pulled by installing its runtime deps, so a narrow install leaves host build-deps
	# missing. The cost of -a is that a few unrelated upstream packages have a recursive
	# kconfig dependency, which is FATAL (it aborts defconfig so nothing builds). We do
	# not build those, so uninstall the known offenders to keep their Config.in out of
	# the scan. (gensio: GENSIO_SCTP <-> libgensio.)
	./scripts/feeds install -a >/dev/null 2>&1
	for broken in gensio; do ./scripts/feeds uninstall "$broken" >/dev/null 2>&1 || true; done

	install_signing_key "$OWRT"
	# Generate the SDK target config, then SELECT which package variants/flags we want
	# (e.g. only the softpipe/amd/llvmpipe mesa variants, MESA_USE_LLVM=y). A fresh SDK
	# defconfig also turns on CONFIG_ALL*, so strip package selections + the ALL flags and
	# force them off, so the mesa build packages ONLY the variants we ask for.
	make defconfig >/dev/null 2>&1
	sed -i -E '/^(# )?CONFIG_PACKAGE_/d; /^CONFIG_ALL[A-Z_]*=/d' .config
	{ echo "CONFIG_ALL=n"; echo "CONFIG_ALL_KMODS=n"; echo "CONFIG_ALL_NONSHARED=n"; } >> .config
	# A bare name -> CONFIG_PACKAGE_<name>=m; an item with '=' is a literal .config line.
	for item in $SELECT; do
		if [ "${item#*=}" != "$item" ]; then
			key="${item%%=*}"
			sed -i "/^${key}[= ]/d;/^# ${key} is not set/d" .config
			echo "$item" >> .config
		else
			echo "CONFIG_PACKAGE_${item}=m" >> .config
		fi
	done
	make defconfig >/dev/null 2>&1
	# DESELECT: force these packages off AFTER defconfig (no defconfig follows, so it sticks
	# even against an auto-selecting DEPENDS). The zfs userland job uses this to drop
	# kmod-fs-zfs: the module is built in the kernel job against our kernel, never here
	# against the SDK's stock kernel. zfs's apk still declares the runtime dep, which apk
	# resolves on-device from the kmods feed.
	for x in ${DESELECT:-}; do
		sed -i "s/^CONFIG_PACKAGE_${x}=.*/# CONFIG_PACKAGE_${x} is not set/" .config
	done

	# Build ONLY the named package dirs. NOT `make package/compile`, which builds every
	# selected package - and the SDK target config always selects ~1000 default kmods,
	# which would rebuild them against the SDK kernel. A per-package compile builds just
	# the package + its userland build-deps (libdrm, LLVM host, ...) and touches no kmods.
	# ZFS_WITH_CONFIG (default all) lets the zfs userland job build user-space only.
	for d in $PKG_DIRS; do
		ZFS_WITH_CONFIG="${ZFS_WITH_CONFIG:-all}" make -j"$JOBS" "package/$d/compile"
	done

	# Drop kmods: no package job produces a kmod we publish (zfs's kmod-fs-zfs is built in
	# the kernel job against our kernel; anything else here would be an SDK-kernel kmod).
	collect_apks "$OWRT" "$OUT/collect"
	echo ">>> done pkg [$PKG_DIRS]: apks=$(ls "$OUT"/collect/*.apk 2>/dev/null | wc -l)"
	exit 0
fi

# ------------------------------------------------------------------ STAGE=index
if [ "$STAGE" = index ]; then
	# Collect every stage's apks (downloaded into OUT/collect) into one signed feed.
	# We need an apk binary + keys; a base SDK provides both (SDK_IN), else fall back to
	# a host apk on PATH.
	IN="${IN:-$OUT/collect}"
	DEST="$OUT/feed"; mkdir -p "$DEST"
	find "$IN" -name '*.apk' -exec cp -f {} "$DEST/" \;
	find "$DEST" \( -name 'kmod-*.apk' -o -name 'kernel-*.apk' \) -delete 2>/dev/null || true
	if [ -n "${SDK_IN:-}" ]; then
		OWRT="${OWRT:-$PWD/sdk}"; rm -rf "$OWRT"; mkdir -p "$OWRT"
		tar -C "$OWRT" --strip-components=1 -xf "$SDK_IN"
		install_signing_key "$OWRT"
		cp -f "$OWRT/public-key.pem" "$OUT/public-key.pem" 2>/dev/null || true
		# add the incus-vm metapackage as pure metadata (no deps compiled), then index.
		gen_incus_vm "$OWRT" "$DEST"
		sign_feed "$OWRT" "$DEST"
	else
		( cd "$DEST" && apk mkndx -o packages.adb ./*.apk )
	fi
	echo ">>> done index: apks=$(ls "$DEST"/*.apk 2>/dev/null | wc -l)"
	exit 0
fi

echo "ERROR: unknown STAGE=$STAGE (want kernel|pkg|index)"; exit 1
