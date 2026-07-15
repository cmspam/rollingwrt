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
gh release view "$TAG" >/dev/null 2>&1 || \
	gh release create "$TAG" -t "$TITLE" -n "$NOTE" >/dev/null 2>&1 || true

err="$(mktemp)"; n=0; ok=0; skip=0
# Existing assets (name + byte size). Skip re-uploading identical ones: the kmods feed
# is ~1000 files that do not change between same-pin builds, and re-uploading them all
# every run trips GitHub's secondary rate limit. Same name + same size = same content
# (a kmod's filename carries its vermagic decimal; a userland rebuild bumps -r).
existing="$(gh release view "$TAG" --json assets --jq '.assets[]|"\(.name) \(.size)"' 2>/dev/null || true)"
for f in "$DIR"/*; do
	[ -f "$f" ] || continue
	n=$((n+1))
	if printf '%s\n' "$existing" | grep -qxF "$(basename "$f") $(stat -c%s "$f" 2>/dev/null)"; then
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

# PRUNE: after uploading the current set, delete release .apk assets that are NOT in it.
# The kmods feed is fully regenerated every kernel build and each build's kmods carry a
# NEW filename (the vermagic decimal changes), so --clobber never overwrites the prior
# build's apks - they would pile up until the release hits GitHub's 1000-asset cap. Prune
# only the stale apks (uploaded the new set first, so the feed is never momentarily empty).
# Not used for the snapshot feed, which intentionally carries prior tracks' apks over.
if [ "${PRUNE:-0}" = 1 ]; then
	keep="$(mktemp)"; for f in "$DIR"/*; do [ -f "$f" ] && basename "$f"; done | sort > "$keep"
	gh release view "$TAG" --json assets --jq '.assets[].name' 2>/dev/null \
		| grep '\.apk$' | sort > "$err"
	pruned=0
	while IFS= read -r a; do
		[ -n "$a" ] || continue
		gh release delete-asset "$TAG" "$a" -y 2>/dev/null && pruned=$((pruned+1))
	done < <(comm -23 "$err" "$keep")
	rm -f "$keep"
	echo ">>> pruned $pruned stale apks from release $TAG"
fi
rm -f "$err"
echo ">>> published $ok new/changed, skipped $skip unchanged (of $n) to release $TAG"
