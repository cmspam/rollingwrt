#!/bin/bash
# rollingWRT CI resolver. Pins this run to OpenWrt's CURRENT published snapshot and
# decides which tracks actually need to build, so an unchanged scheduled day does
# nothing and a single package bump rebuilds only its track.
#
# Pin: rollingWRT builds the kernel against OpenWrt's own openwrt-toolchain download and
# the packages against OpenWrt's official SDK download. OpenWrt publishes those ONLY for
# the newest snapshot, so the source, the toolchain and the SDK must all come from the
# same snapshot - the one named in the target's version.buildinfo. We read it live here;
# config/SNAPSHOT_PIN is no longer the build pin (update.yml still records it).
#
# Gating signals, compared against the last published build (the snapshot release's
# manifest.json, written by the build's index job):
#   kernel : the snapshot's x86 target kernel version. When it moves, the kernel and
#            every kmod are ABI-invalidated - rebuild the kernel track and zfs (its kmod).
#   <pkg>  : the PKG_VERSION pinned in our feed Makefile (update.yml bumps these to latest
#            upstream on its own cadence and commits, which triggers a forced push build).
# A push rebuilds ONLY the tracks whose files it changed (git diff of the push): a change
# under feed/incus rebuilds the incus track, not the ~1.5h kernel. A change to shared build
# glue (build/*.sh, Containerfile, .github, overlay) rebuilds everything, since it can affect
# every track. A manual dispatch with `force` (or the first ever build, which has no manifest)
# rebuilds every track; a dispatch without `force` is version-gated like the daily schedule.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # repo/
FEED="${FEED:-$HERE/feed}"
BASE="${OPENWRT_SNAPSHOT_BASE:-https://downloads.openwrt.org/snapshots/targets/x86/64}"
GH_RAW="https://raw.githubusercontent.com/openwrt/openwrt"
REPO_SLUG="${REPO_SLUG:-cmspam/rollingwrt}"
MANIFEST_URL="${MANIFEST_URL:-https://github.com/$REPO_SLUG/releases/download/snapshot/manifest.json}"
EVENT="${EVENT:-workflow_dispatch}"
FORCE="${FORCE:-false}"
BEFORE="${BEFORE:-}"     # push only: commit before the push (github.event.before)
AFTER="${AFTER:-HEAD}"   # push only: the pushed commit (github.sha)

out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT"; echo "resolve: $1=$2" >&2; }
jget() { # json-text key -> value ("" if absent)
	printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}
feedver() { # package -> its feed Makefile PKG_VERSION ("" if absent)
	sed -n 's/^PKG_VERSION[[:space:]]*[:?]*=[[:space:]]*//p' "$FEED/$1/Makefile" 2>/dev/null | head -1
}

# --- pin: the published snapshot (source + toolchain + SDK all aligned) ----------
list="$(curl -sfL "$BASE/")" || { echo "resolve: cannot list $BASE" >&2; exit 1; }
tc_file="$(printf '%s' "$list" | grep -oE 'openwrt-toolchain[^"]*\.tar\.zst' | head -1)"
sdk_file="$(printf '%s' "$list" | grep -oE 'openwrt-sdk[^"]*\.tar\.zst' | head -1)"
rev="$(curl -sfL "$BASE/version.buildinfo" | tr -d '[:space:]')"   # e.g. r35335-b496e07d0f
pin="${rev#*-}"
[ -n "$tc_file" ] && [ -n "$sdk_file" ] && [ -n "$pin" ] \
	|| { echo "resolve: incomplete (tc=$tc_file sdk=$sdk_file pin=$pin)" >&2; exit 1; }
out pin "$pin"; out rev "$rev"
out tc_url "$BASE/$tc_file"; out sdk_url "$BASE/$sdk_file"

# --- kernel version at that exact snapshot commit --------------------------------
patchver="$(curl -fsSL "$GH_RAW/$pin/target/linux/x86/Makefile" | sed -n 's/^KERNEL_PATCHVER[[:space:]]*[:?]*=[[:space:]]*//p' | head -1)"
[ -n "$patchver" ] || { echo "resolve: could not read KERNEL_PATCHVER at $pin" >&2; exit 1; }
kver="$(curl -fsSL "$GH_RAW/$pin/target/linux/generic/kernel-$patchver" | sed -n "s/^LINUX_VERSION-$patchver[[:space:]]*=[[:space:]]*//p" | head -1)"
kernel_now="$patchver$kver"                       # e.g. 6.18.38
out kernel_version "$kernel_now"

# --- gate ------------------------------------------------------------------------
manifest="$(curl -sfL "$MANIFEST_URL" 2>/dev/null || true)"

# forced = rebuild every track. A manual dispatch with force=true, or the first ever build
# (no manifest to diff against), forces all. A push instead gates per track by the files it
# changed (below); only a push touching shared build glue escalates to forced.
forced=false
{ [ "$EVENT" = workflow_dispatch ] && [ "$FORCE" = true ]; } && forced=true
[ -z "$manifest" ] && forced=true

# --- push: map the changed files to the tracks they affect -----------------------
# Version-gating (below) catches UPSTREAM moves (a new snapshot, a bumped PKG_VERSION) but
# not edits to our own recipes/scripts that leave the version string unchanged. So a push
# also rebuilds any track whose files it touched.
pt_kernel=false; pt_zfs=false; pt_gpu=false; pt_main=false
if [ "$EVENT" = push ] && [ "$forced" != true ]; then
	if [ -z "$BEFORE" ] || ! git -C "$HERE" rev-parse -q --verify "${BEFORE}^{commit}" >/dev/null 2>&1; then
		forced=true                                     # no diff base (new branch/force-push): rebuild all
	else
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			case "$f" in
				build/build.sh|build/Containerfile|build/ci-resolve.sh|build/gh-publish.sh|.github/*|overlay/*)
					forced=true ;;                          # shared glue: can affect every track
				config/*)                    pt_kernel=true ;;
				feed/zfs/*)                  pt_zfs=true; pt_kernel=true ;;   # userland here + its kmod in the kernel job
				feed/virglrenderer/*|feed/qemu/*|feed/qemu-firmware-edk2/*|feed/numactl/*|feed/usbredir/*)
					pt_gpu=true ;;
				feed/cowsql/*|feed/cowsql-raft/*|feed/incus/*|feed/incus-ui/*|feed/incus-ui-proxy/*|feed/luci-app-incus/*|feed/incus-vm/*)
					pt_main=true ;;
				feed/systemd-boot/*|feed/tpm2-tss/*|feed/tpm2-tools/*|feed/sbctl/*|feed/rollingwrt-boot/*)
					pt_main=true ;;                         # the boot job shares the build_main gate
				feed/*)                      forced=true ;;    # an unrecognised feed package: rebuild all, never miss it
				*) : ;;                                     # docs/planning/etc: nothing to build
			esac
		done < <(git -C "$HERE" diff --name-only "$BEFORE" "$AFTER" 2>/dev/null)
	fi
fi

changed() { # key currentvalue path_touched -> "true" if forced, path-touched, or version differs
	[ "$forced" = true ] && { echo true; return; }
	{ [ "${3:-false}" = true ] || [ "$(jget "$manifest" "$1")" != "$2" ]; } && echo true || echo false
}
kernel_changed="$(changed kernel "$kernel_now" "$pt_kernel")"
zfs_changed="$(changed zfs "$(feedver zfs)" "$pt_zfs")"
qemu_changed="$(changed qemu "$(feedver qemu)" "$pt_gpu")"
incus_changed="$(changed incus "$(feedver incus)" "$pt_main")"
cowsql_changed="$(changed cowsql "$(feedver cowsql)" "$pt_main")"

# job gates. The kernel job builds the kernel + every kmod INCLUDING kmod-fs-zfs (against
# our kernel), so it rebuilds on a kernel bump (ABI-invalidates every kmod) OR a zfs bump
# (new module). The zfs USERLAND builds separately and depends only on the zfs version,
# not the kernel; qemu/incus/boot userland likewise rebuild only on their own bump or a
# forced run.
yesno() { { [ "$1" = true ] || [ "$2" = true ]; } && echo 1 || echo 0; }
build_kernel="$(yesno "$kernel_changed" "$zfs_changed")"
build_zfs="$(yesno "$zfs_changed" false)"
build_gpu="$(yesno "$qemu_changed" false)"
build_main="$(yesno "$incus_changed" "$cowsql_changed")"
out build_kernel "$build_kernel"
out build_zfs "$build_zfs"
out build_gpu "$build_gpu"
out build_main "$build_main"
{ [ "$build_kernel$build_zfs$build_gpu$build_main" != 0000 ] && out build_any 1; } || out build_any 0
echo "resolve: pin=$pin kver=$kernel_now forced=$forced (event=$EVENT)" >&2
