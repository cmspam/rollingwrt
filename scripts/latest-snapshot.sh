#!/bin/sh
# Print the current OpenWrt snapshot (main) commit. rollingWRT pins this in
# config/SNAPSHOT_PIN; the update workflow moves it on our cadence.
git ls-remote https://github.com/openwrt/openwrt.git refs/heads/main | cut -f1
