#!/usr/bin/env bash
# Resolve the latest upstream version of each package and rewrite its Makefile's
# PKG_VERSION / PKG_HASH in place. Prints "<pkg> <old> -> <new>" for each change
# and exits 0 whether or not anything changed; CI commits the diff if non-empty.
#
# Sources differ per package, so each has a small resolver. Two packages are not
# bumped here:
#   virglrenderer    - carries the Xe native-context patch; a version bump may
#                      need the patch rebased, so it is bumped by hand.
#   kmod-vhost-vsock - its source is the kernel shipped by the target OpenWrt
#                      SDK, not an upstream release; scripts/sync-kmod-src.sh
#                      refreshes it when the OpenWrt version changes.
# The build runs this at the start of every daily run and commits the result, so a
# package is at most one day behind its upstream release.
set -euo pipefail
FEED="${FEED:-$(cd "$(dirname "$0")/../feed" && pwd)}"

note() { printf '%s\n' "$*" >&2; }

# sha256 of a URL without keeping the file around.
url_sha256() { curl -fsSL "$1" | sha256sum | cut -d' ' -f1; }

# Read PKG_VERSION from a feed Makefile.
cur_ver() { sed -n 's/^PKG_VERSION:=//p' "$FEED/$1/Makefile" | head -1; }

# Rewrite PKG_VERSION and PKG_HASH in a feed Makefile.
set_ver_hash() { # pkg version hash
	local mk="$FEED/$1/Makefile"
	sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$2/" "$mk"
	sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$3/" "$mk"
}

# Latest non-prerelease tag of a GitHub repo, with leading v stripped.
gh_latest() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1; }

bump_github_tarball() { # pkg  owner/repo  tarball-url-template ({v} = version)
	local pkg="$1" repo="$2" tmpl="$3" new old url
	new="$(gh_latest "$repo")"; old="$(cur_ver "$pkg")"
	[ -n "$new" ] || { note "$pkg: could not resolve latest"; return 0; }
	[ "$new" != "$old" ] || return 0
	url="${tmpl//\{v\}/$new}"
	set_ver_hash "$pkg" "$new" "$(url_sha256 "$url")"
	echo "$pkg $old -> $new"
}

# --- incus: GitHub release tarball. The top directory inside it is not derivable
#     from the version (7.4.0 unpacks to incus-7.4, 7.5.1 to incus-7.5.1), so
#     PKG_BUILD_DIR is read from the tarball itself. ---
bump_incus() {
	local new old tgz top
	new="$(gh_latest lxc/incus)"; old="$(cur_ver incus)"
	[ -n "$new" ] && [ "$new" != "$old" ] || return 0
	tgz="$(mktemp)"
	curl -fsSL -o "$tgz" "https://github.com/lxc/incus/releases/download/v$new/incus-$new.tar.gz"
	top="$(tar tzf "$tgz" | sed -n '1s#/.*##p')"
	[ -n "$top" ] || { note "incus: could not read top directory of incus-$new.tar.gz"; rm -f "$tgz"; return 0; }
	set_ver_hash incus "$new" "$(sha256sum "$tgz" | cut -d' ' -f1)"
	rm -f "$tgz"
	sed -i "s#^PKG_BUILD_DIR:=.*#PKG_BUILD_DIR:=\$(BUILD_DIR)/$top#" "$FEED/incus/Makefile"
	# incus-vm is a metapackage over the same release; it carries incus's version.
	sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$new/" "$FEED/incus-vm/Makefile"
	echo "incus $old -> $new"
}

# --- incus-ui: the newest incus-ui-canonical .deb in the Zabbly Packages index
#     (highest version, then newest build stamp). Zabbly removes superseded debs
#     from the pool, so the pin must always follow the index. ---
bump_incus_ui() {
	local mk pkgs deb ver new old hash
	mk="$FEED/incus-ui/Makefile"
	pkgs="$(curl -fsSL https://pkgs.zabbly.com/incus/stable/dists/trixie/main/binary-amd64/Packages)"
	deb="$(printf '%s' "$pkgs" | sed -n 's#^Filename: .*/\(incus-ui-canonical_[0-9.]*-debian13-[0-9]*_amd64.deb\)#\1#p' \
		| sed 's/^incus-ui-canonical_\([0-9.]*\)-debian13-\([0-9]*\)_amd64.deb$/\1 \2 &/' \
		| sort -k1,1V -k2,2n | tail -1 | cut -d' ' -f3)"
	[ -n "$deb" ] || { note "incus-ui: no .deb in the Zabbly index"; return 0; }
	ver="$(printf '%s' "$deb" | sed -n 's/^incus-ui-canonical_\([0-9.]*\)-debian13-.*/\1/p')"
	new="$(printf '%s' "$deb" | sed -n 's/.*-debian13-\([0-9]*\)_amd64.deb/\1/p')"
	old="$(sed -n 's/^PKG_DEB_STAMP:=//p' "$mk")"
	[ "$new" != "$old" ] || return 0
	hash="$(url_sha256 "https://pkgs.zabbly.com/incus/stable/pool/main/i/incus/$deb")"
	sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$ver/;s/^PKG_DEB_STAMP:=.*/PKG_DEB_STAMP:=$new/;s/^PKG_HASH:=.*/PKG_HASH:=$hash/" "$mk"
	echo "incus-ui $old -> $new"
}

# --- zfs: openzfs tags the release zfs-X.Y.Z, not vX.Y.Z ---
bump_zfs() {
	local tag new old; old="$(cur_ver zfs)"
	tag="$(curl -fsSL https://api.github.com/repos/openzfs/zfs/releases/latest | sed -n 's/.*"tag_name": *"zfs-\([^"]*\)".*/\1/p' | head -1)"
	[ -n "$tag" ] && [ "$tag" != "$old" ] || return 0
	set_ver_hash zfs "$tag" "$(url_sha256 "https://github.com/openzfs/zfs/releases/download/zfs-$tag/zfs-$tag.tar.gz")"
	echo "zfs $old -> $tag"
}

# --- qemu: newest release tarball on download.qemu.org. The digits-only match skips the
#     rc/alpha names, so this only ever picks a final release. feed/qemu is OpenWrt's
#     recipe plus our native-context flags and it runs ahead of the version OpenWrt ships,
#     so a point release is routine but a major bump can need the recipe re-synced from
#     the snapshot's feeds/packages/utils/qemu (re-applying the virgl flags). ---
bump_qemu() {
	local new old; old="$(cur_ver qemu)"
	new="$(curl -fsSL https://download.qemu.org/ | sed -n 's/.*qemu-\([0-9][0-9.]*\)\.tar\.xz".*/\1/p' | sort -V | tail -1)"
	[ -n "$new" ] && [ "$new" != "$old" ] || return 0
	set_ver_hash qemu "$new" "$(url_sha256 "https://download.qemu.org/qemu-$new.tar.xz")"
	echo "qemu $old -> $new"
}

bump_github_tarball cowsql      cowsql/cowsql "https://codeload.github.com/cowsql/cowsql/tar.gz/refs/tags/v{v}"
bump_github_tarball cowsql-raft cowsql/raft   "https://codeload.github.com/cowsql/raft/tar.gz/refs/tags/v{v}"
bump_zfs
bump_incus
bump_incus_ui
bump_qemu
