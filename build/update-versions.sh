#!/bin/bash
# Resolve the latest STABLE upstream release for each auto-tracked userland package
# and rewrite its feed Makefile's PKG_VERSION + PKG_HASH before a build. Run by CI
# ahead of build.sh so the rolling snapshot always carries current userland.
#
# Fail loud: any package whose version or source hash cannot be resolved aborts the
# whole script (a build must never silently ship a stale or wrong pin). Our feed
# patches are best-effort: this script does not touch them, so if a bump breaks a
# patch the package build fails at apply time, which is the intended loud signal.
#
# NOT auto-tracked here (by design):
#   - the kernel + all kmods: they follow the OpenWrt snapshot pin (config/SNAPSHOT_PIN).
#   - virglrenderer: pinned until the Xe native-context patch lands upstream, then
#     dropped; the maintainer drives that by hand. Pass --with-virgl to include it.
#
# Usage: update-versions.sh [--dry-run] [--with-virgl]
set -euo pipefail
FEED="${FEED:-$(cd "$(dirname "$0")/../feed" && pwd)}"
DRY=0; WITH_VIRGL=0
for a in "$@"; do
	case "$a" in
		--dry-run) DRY=1 ;;
		--with-virgl) WITH_VIRGL=1 ;;
		*) echo "unknown arg: $a" >&2; exit 2 ;;
	esac
done
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# --- resolvers: echo the bare upstream version (no v/zfs- prefix) ---------------
gh_latest() { # owner/repo -> tag_name
	# Use a token when present (GITHUB_TOKEN in CI) so the anonymous 60/hr API rate
	# limit on shared runner IPs does not make resolution flap.
	local auth=()
	[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
	curl -fsSL --retry 3 "${auth[@]}" "https://api.github.com/repos/$1/releases/latest" \
		| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}
resolve() { # package -> version
	case "$1" in
		incus)       gh_latest lxc/incus       | sed 's/^v//' ;;
		zfs)         gh_latest openzfs/zfs      | sed 's/^zfs-//' ;;
		cowsql)      gh_latest cowsql/cowsql    | sed 's/^v//' ;;
		cowsql-raft) gh_latest cowsql/raft      | sed 's/^v//' ;;
		qemu)        curl -fsSL --retry 3 https://download.qemu.org/ \
			| grep -oE 'qemu-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz' | sed 's/^qemu-//; s/\.tar\.xz$//' \
			| sort -V | tail -1 ;;
		virglrenderer) curl -fsSL --retry 3 \
			"https://gitlab.freedesktop.org/api/v4/projects/virgl%2Fvirglrenderer/repository/tags?per_page=20" \
			| grep -oE '"name":"[0-9][^"]*"' | sed 's/"name":"//; s/"$//' | sort -V | tail -1 ;;
		*) echo "no resolver for $1" >&2; return 1 ;;
	esac
}
# --- source URL for a resolved version (matches each feed Makefile) -------------
source_url() { # package version -> url
	case "$1" in
		incus)       echo "https://github.com/lxc/incus/releases/download/v$2/incus-$2.tar.gz" ;;
		zfs)         echo "https://github.com/openzfs/zfs/releases/download/zfs-$2/zfs-$2.tar.gz" ;;
		qemu)        echo "https://download.qemu.org/qemu-$2.tar.xz" ;;
		virglrenderer) echo "https://gitlab.freedesktop.org/virgl/virglrenderer/-/archive/$2/virglrenderer-$2.tar.gz" ;;
		cowsql)      echo "https://codeload.github.com/cowsql/cowsql/tar.gz/refs/tags/v$2" ;;
		cowsql-raft) echo "https://codeload.github.com/cowsql/raft/tar.gz/refs/tags/v$2" ;;
	esac
}

PKGS="incus zfs qemu cowsql cowsql-raft"
[ "$WITH_VIRGL" = 1 ] && PKGS="$PKGS virglrenderer"

rc=0
for p in $PKGS; do
	mk="$FEED/$p/Makefile"
	[ -f "$mk" ] || { echo "FAIL $p: no $mk" >&2; rc=1; continue; }
	ver="$(resolve "$p")" || { echo "FAIL $p: version resolve" >&2; rc=1; continue; }
	[ -n "$ver" ] || { echo "FAIL $p: empty version" >&2; rc=1; continue; }
	url="$(source_url "$p" "$ver")"
	if ! curl -fsSL --retry 3 -o "$WORK/$p.src" "$url"; then
		echo "FAIL $p: download $url" >&2; rc=1; continue
	fi
	hash="$(sha256sum "$WORK/$p.src" | cut -d' ' -f1)"
	[ -n "$hash" ] || { echo "FAIL $p: empty hash" >&2; rc=1; continue; }

	oldver="$(sed -n 's/^PKG_VERSION:=//p' "$mk" | head -1)"
	oldhash="$(sed -n 's/^PKG_HASH:=//p' "$mk" | head -1)"
	if [ "$ver" = "$oldver" ] && [ "$hash" = "$oldhash" ]; then
		echo "ok   $p $ver (unchanged)"
		continue
	fi
	echo "BUMP $p $oldver -> $ver"
	echo "     hash $oldhash -> $hash"
	if [ "$DRY" = 0 ]; then
		sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$ver/" "$mk"
		sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$hash/" "$mk"
	fi
done
exit $rc
