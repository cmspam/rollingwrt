#!/bin/bash
# Build the rollingWRT installer medium.
#
# The medium is a bootable x86-64 image (UEFI + legacy BIOS via grub) carrying
# `rollingwrt-install` plus the disk and crypto tools it needs. Booting it gives a
# shell where `rollingwrt-install` lays rollingWRT onto a real disk, pulling the
# add-on userland (incus, zfs, ...) from our feed at install time.
#
# It runs OUR kernel, not OpenWrt's stock one, so it has TPM support (the stock
# kernel builds none) and matches the kernel it installs. The base rootfs + tools
# come from OpenWrt's official x86-64 ImageBuilder; our kernel and its modules are
# then swapped in over the stock ones. Output:
#   out/rollingwrt-installer-<rev>-efi.img.gz   (dd to USB, or boot in a VM)
#
# Usage: build-medium.sh [out-dir]      (env: PUBKEY_URL or PUBKEY_FILE = our feed key)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/out}"; mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

BASE="https://downloads.openwrt.org/snapshots/targets/x86/64"
IB_FILE="$(curl -sfL "$BASE/" | grep -oE 'openwrt-imagebuilder[^"]*\.tar\.zst' | head -1)"
[ -n "$IB_FILE" ] || { echo "cannot find the x86-64 ImageBuilder" >&2; exit 1; }
REV="$(curl -sfL "$BASE/version.buildinfo" | tr -d '[:space:]')"; REV="${REV#*-}"

echo "==> downloading ImageBuilder ($IB_FILE)"
curl -sfL "$BASE/$IB_FILE" -o "$WORK/ib.tar.zst"
tar -C "$WORK" --zstd -xf "$WORK/ib.tar.zst"
IB="$WORK/$(basename "$IB_FILE" .tar.zst)"

# FILES overlay baked into the image root: the installer, our feed's public key
# (so the installer can pull our packages onto the target), and a login banner.
FILES="$WORK/files"
mkdir -p "$FILES/usr/bin" "$FILES/etc/apk/keys" "$FILES/etc/profile.d"
install -m0755 "$HERE/rollingwrt-install" "$FILES/usr/bin/rollingwrt-install"
install -m0644 "$HERE/rollingwrt-common.sh" "$FILES/usr/bin/rollingwrt-common.sh"

# our feed's signing public key (trusted so the installer's apk pulls our packages)
if [ -n "${PUBKEY_FILE:-}" ]; then cp "$PUBKEY_FILE" "$FILES/etc/apk/keys/rollingwrt.pem"
else curl -sfL "${PUBKEY_URL:-https://github.com/cmspam/rollingwrt/releases/download/snapshot/public-key.pem}" \
	-o "$FILES/etc/apk/keys/rollingwrt.pem" || echo "WARN: could not fetch our public key; installer will need it at run time" >&2
fi

cat > "$FILES/etc/profile.d/99-rollingwrt-installer.sh" <<'BANNER'
[ -t 0 ] && cat <<EOF

  rollingWRT installer.  This is a live environment, nothing is installed yet.
  Run:  rollingwrt-install
  It will ask a few questions, then install rollingWRT to a disk you choose.

EOF
BANNER

# The installer's runtime deps, on top of the base image. OpenWrt ships gptfdisk
# split, so we want sgdisk (scriptable), not the interactive gdisk. dosfstools =
# mkfs.fat; kmod-dm + the crypto set let cryptsetup do aes-xts LUKS on the medium's
# stock kernel and read the vfat ESP; curl/ca-bundle/openssl-util for the key fetch
# and the TPM policy key. cryptsetup pulls its own further deps.
PKGS="sgdisk cryptsetup dosfstools parted lsblk blkid losetup e2fsprogs wipefs \
curl ca-bundle openssl-util \
kmod-dm kmod-crypto-xts kmod-crypto-ecb kmod-crypto-user kmod-fs-vfat"

echo "==> building image (snapshot $REV)"
make -C "$IB" image PROFILE="generic" PACKAGES="$PKGS" FILES="$FILES" \
	EXTRA_IMAGE_NAME="rollingwrt-installer" >/dev/null

# prefer the ext4 image: its rootfs is writable, so we can swap modules into it (the
# squashfs variant is read-only). ImageBuilder emits both.
img="$(find "$IB/bin/targets/x86/64" -name '*rollingwrt-installer*ext4-combined-efi.img.gz' | head -1)"
[ -n "$img" ] || img="$(find "$IB/bin/targets/x86/64" -name '*rollingwrt-installer*combined-efi.img.gz' | head -1)"
[ -n "$img" ] || { echo "image build produced no combined-efi image" >&2; ls "$IB/bin/targets/x86/64" >&2; exit 1; }

# The base image boots OpenWrt's stock kernel, which builds no TPM support (CONFIG_TCG_CRB
# and TCG_TIS are off), so it cannot seal a LUKS key at install time. Swap in OUR kernel so
# the medium runs the same kernel it installs. grub loads /boot/vmlinuz off the ESP with
# root=PARTUUID and no initramfs, so it suffices to replace that vmlinuz and the rootfs
# /lib/modules with ours. We install our kernel plus exactly the kmods the base image already
# carries, so nothing the medium loads is left at a mismatched vermagic.
echo "==> swapping in our kernel"
set -x
OWRT_SNAP="https://downloads.openwrt.org/snapshots"
RWRT_REL="${RWRT_REL:-https://github.com/cmspam/rollingwrt/releases/download}"
APK="$IB/staging_dir/host/bin/apk"

gzip -dk "$img"; IMG="${img%.gz}"
LOOP="$(sudo losetup -Pf --show "$IMG")"
ESPM="$(mktemp -d)"; ROOTM="$(mktemp -d)"
sudo mount "${LOOP}p1" "$ESPM"
sudo mount "${LOOP}p2" "$ROOTM"

# the kmods the base image carries (so we install OUR versions of the same set).
# apk's exit must not kill the script (it runs under set -e/pipefail), so read to a file.
pkgtmp="$(mktemp)"
sudo "$APK" --root "$ROOTM" list --installed > "$pkgtmp" 2>&1 || echo "apk list --installed exit $?"
# strip the version suffix (-6.18.38-r1): a bare name resolves to OUR .decimal build,
# a versioned name would pin the stock version, which is not in our feed.
KMODS="$(grep -oE '^kmod-[a-z0-9._-]+' "$pkgtmp" | sed -E 's/-[0-9][0-9.]*-r[0-9]+$//' | sort -u | tr '\n' ' ')"
echo "base image kmods: $(printf '%s' "$KMODS" | wc -w)"
# fallback (apk list gave nothing): a set covering what an installer medium needs
[ -n "$KMODS" ] || KMODS="kmod-crypto-xts kmod-crypto-ecb kmod-crypto-user kmod-crypto-sha256 kmod-crypto-hmac kmod-dm kmod-fs-vfat kmod-tpm kmod-tpm-crb kmod-tpm-tis kmod-e1000e kmod-e1000 kmod-igb kmod-igc kmod-ixgbe kmod-r8169 kmod-tg3 kmod-nvme kmod-usb-storage kmod-nft-core kmod-button-hotplug"

# our kernel + those kmods, from our feed, into a temp root (offline-install idiom:
# IPKG_INSTROOT + pre-made runtime dirs + --force-no-chroot so post-installs do not hang)
TR="$(mktemp -d)"
"$APK" --root "$TR" --initdb add >/dev/null 2>&1 || true
mkdir -p "$TR/etc/apk/keys"   # --initdb makes the db, not the /etc/apk config dir
{ echo "$OWRT_SNAP/targets/x86/64/packages/packages.adb"
  echo "$OWRT_SNAP/packages/x86_64/base/packages.adb"
  echo "$RWRT_REL/snapshot/packages.adb"
  for b in 1 2 3; do echo "$RWRT_REL/snapshot-kmods-$b/packages.adb"; done
} > "$TR/etc/apk/repositories"
"$APK" --root "$TR" --allow-untrusted update >/dev/null 2>&1 || true   # nonzero on a benign repo warning; the add below is the real check
mkdir -p "$TR/var/lock" "$TR/var/run" "$TR/tmp" "$TR/etc/rc.d"
# shellcheck disable=SC2086
IPKG_INSTROOT="$TR" "$APK" --root "$TR" --allow-untrusted --force-no-chroot --preserve-env add rollingwrt-kernel $KMODS >/dev/null 2>&1 || true
KVER="$(ls "$TR/lib/modules" 2>/dev/null | head -1)"
[ -n "$KVER" ] && [ -f "$TR/boot/vmlinuz-$KVER" ] || { echo "our kernel install produced no vmlinuz/modules" >&2; exit 1; }

sudo cp -f "$TR/boot/vmlinuz-$KVER" "$ESPM/boot/vmlinuz"
sudo rm -rf "$ROOTM/lib/modules/$KVER"
sudo cp -a "$TR/lib/modules/$KVER" "$ROOTM/lib/modules/$KVER"
sudo depmod -b "$ROOTM" "$KVER"
sync; sudo umount "$ESPM" "$ROOTM"; sudo losetup -d "$LOOP"

gzip -f "$IMG"
cp "$IMG.gz" "$OUT/rollingwrt-installer-$REV-efi.img.gz"
echo "==> $OUT/rollingwrt-installer-$REV-efi.img.gz (on our kernel $KVER)"
