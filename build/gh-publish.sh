#!/bin/bash
# Publish a directory of files to a GitHub release tag, resilient to GitHub's SECONDARY
# rate limit. The kmods feed is ~1000 apks (≈330 per bucket) and uploading them fast (as
# softprops/action-gh-release does, in parallel) trips "You have exceeded a secondary rate
# limit". We upload one asset at a time, pace gently, and back off when the limit is hit.
# Seed uploads take a while; gated rebuilds change few files and finish fast.
#
# Usage: GH_TOKEN=... gh-publish.sh <tag> <dir> [release title]
set -uo pipefail
TAG="${1:?tag}"; DIR="${2:?dir}"; TITLE="${3:-rollingWRT $TAG}"
command -v gh >/dev/null || { echo "ERROR: gh not found" >&2; exit 1; }

NOTE="An apk package repository for rollingWRT, an OpenWrt-based x86-64 distribution. Add this release's download URL to a device's apk repositories to install these packages."
# --prerelease: these tags host the apk feeds, not a user download, so they must never
# take GitHub's "Latest release" badge from the installer ISO. Only sets it on CREATE (a
# fresh feed after a wipe); an existing tag keeps whatever flag it has, and we only upload.
gh release view "$TAG" >/dev/null 2>&1 || \
	gh release create "$TAG" -t "$TITLE" -n "$NOTE" --prerelease >/dev/null 2>&1 || true

err="$(mktemp)"; n=0; ok=0; skip=0
# Existing assets (name + byte size). Skip re-uploading identical ones: the kmods feed
# is ~1000 files that do not change between same-pin builds, and re-uploading them all
# every run trips GitHub's secondary rate limit. Same name + same size = same content
# (a kmod's filename carries its vermagic decimal; a userland rebuild bumps -r).
existing="$(gh release view "$TAG" --json assets --jq '.assets[]|"\(.name) \(.size)"' 2>/dev/null || true)"
for f in "$DIR"/*; do
	[ -f "$f" ] || continue
	n=$((n+1))
	bn="$(basename "$f")"
	# The name+size skip assumes same-name+same-size means same content. That holds for the
	# kmods (name carries the vermagic) and -r-bumped userland, but NOT for a metapackage
	# regenerated every build with a fixed version and non-deterministic bytes (incus-vm):
	# its apk stays the same size while its content/hash changes, so skipping it leaves a
	# stale apk that no longer matches the freshly-built index (apk then fails with an ADB
	# integrity error). FORCE_UPLOAD is a glob of basenames that must always be re-uploaded.
	# The name+size skip is a rate-limit optimization for the ~1000 kmod .apks. It is WRONG
	# for a file whose content can change without its size changing: the small metadata files
	# (manifest.json - the build gate reads it; packages.adb - the index; public-key.pem) and
	# a regenerated fixed-version apk (incus-vm, via FORCE_UPLOAD). So only .apk files are
	# size-skippable; everything else is always re-uploaded (there are only a few, all small).
	force=0
	case "$bn" in *.apk) case "${FORCE_UPLOAD:-}" in "") : ;; *) case "$bn" in $FORCE_UPLOAD) force=1;; esac ;; esac ;; *) force=1 ;; esac
	if [ "$force" = 0 ] && printf '%s\n' "$existing" | grep -qxF "$bn $(stat -c%s "$f" 2>/dev/null)"; then
		skip=$((skip+1)); continue
	fi
	# A kernel bump renames all ~1000 kmods, so they all upload at once - enough to trip
	# GitHub's secondary rate limit. Ride it out: the limit clears after ~1min of quiet,
	# so on a hit wait a flat 60s and keep retrying for a long while rather than failing.
	for attempt in $(seq 1 20); do
		if gh release upload "$TAG" "$f" --clobber >"$err" 2>&1; then ok=$((ok+1)); break; fi
		if grep -qiE "rate limit|secondary|abuse" "$err"; then
			echo "  rate-limited on $(basename "$f"); wait 60s (attempt $attempt/20)" >&2
			sleep 60
		else
			sleep 5
		fi
		if [ "$attempt" = 20 ]; then
			echo "ERROR: failed to upload $(basename "$f") after retries:" >&2
			cat "$err" >&2; rm -f "$err"; exit 1
		fi
	done
	sleep 1   # gentle pace so we trip the limit rarely
done
rm -f "$err"

# PRUNE: delete only SUPERSEDED .apk assets - an older version of a package that the new
# feed ($DIR) republishes with a different filename (a kmod's vermagic decimal moved, or a
# userland -r bumped). A release apk is pruned ONLY when $DIR contains another apk with the
# SAME package name. A package that $DIR does not contain AT ALL is KEPT, never deleted:
# that protects against a build that is missing tracks (e.g. a failed `prev` download on a
# gated snapshot build) silently wiping the whole feed. Package name = filename up to the
# first '-<digit>' segment.
pkgname() { basename "$1" | sed -E 's/-[0-9][^/]*$//'; }
if [ "${PRUNE:-0}" = 1 ]; then
	keepfiles="$(mktemp)"; keepnames="$(mktemp)"
	for f in "$DIR"/*.apk; do [ -f "$f" ] || continue; basename "$f" >> "$keepfiles"; pkgname "$f" >> "$keepnames"; done
	sort -u "$keepnames" -o "$keepnames"
	pruned=0
	while IFS= read -r a; do
		[ -n "$a" ] || continue
		grep -qxF "$a" "$keepfiles" && continue                       # exact match: current, keep
		grep -qxF "$(pkgname "$a")" "$keepnames" || continue          # package absent entirely: KEEP (never nuke)
		gh release delete-asset "$TAG" "$a" -y 2>/dev/null && pruned=$((pruned+1))
	done < <(gh release view "$TAG" --json assets --jq '.assets[].name' 2>/dev/null | grep '\.apk$')
	rm -f "$keepfiles" "$keepnames"
	echo ">>> pruned $pruned superseded apks from release $TAG"
fi
rm -f "$err"
echo ">>> published $ok new/changed, skipped $skip unchanged (of $n) to release $TAG"
