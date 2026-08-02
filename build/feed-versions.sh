#!/bin/sh
# Print "<package> <version> <track>" for every package in feed/, one per line, where
# track is the build job that produces it (kernel, zfs, gpu, main) or "-" for a package
# no job builds.
#
# This is the single definition of what version a feed package is at and who builds it,
# and two places that must agree read it: build/ci-resolve.sh gates each build track on
# it, and the build's index job records it in manifest.json for the next run to compare
# against. If the two ever disagreed, a package would either rebuild on every run or
# never rebuild at all.
#
# The version is PKG_VERSION-rPKG_RELEASE, so a recipe revision counts as a change.
# Two packages need more than PKG_VERSION:
#   incus-ui          PKG_VERSION is only incus's major.minor; the Zabbly .deb build
#                     stamp is what identifies the payload.
#   rollingwrt-kernel has no PKG_VERSION. It is versioned by the kernel it packages,
#                     which the resolver gates on separately.
set -eu
FEED="${FEED:-$(cd "$(dirname "$0")/../feed" && pwd)}"

mkvar() { sed -n "s/^$2[[:space:]]*[:?]*=[[:space:]]*//p" "$FEED/$1/Makefile" | head -1; }

# Which job builds a package. A package missing from this list prints track "-", which
# the resolver treats as a full rebuild rather than quietly leaving it out.
track_of() {
	case "$1" in
	rollingwrt-kernel)                                       echo kernel ;;
	zfs)                                                     echo zfs ;;
	virglrenderer|qemu|qemu-firmware-edk2|numactl|usbredir)   echo gpu ;;
	cowsql|cowsql-raft|incus|incus-ui|incus-ui-proxy|luci-app-incus|incus-vm)
	                                                         echo main ;;
	systemd-boot|tpm2-tss|tpm2-tools|sbctl|rollingwrt-boot)   echo main ;;   # the boot job shares the main gate
	*)                                                       echo - ;;
	esac
}

for dir in "$FEED"/*/; do
	pkg="${dir%/}"; pkg="${pkg##*/}"
	[ -f "$FEED/$pkg/Makefile" ] || continue
	ver="$(mkvar "$pkg" PKG_VERSION)"
	rel="$(mkvar "$pkg" PKG_RELEASE)"
	case "$pkg" in
	incus-ui) ver="$ver-$(mkvar "$pkg" PKG_DEB_STAMP)" ;;
	esac
	echo "$pkg ${ver:-0}-r${rel:-1} $(track_of "$pkg")"
done
