# rollingWRT installer shared constants and helpers.
# Sourced by rollingwrt-install and the image builders so they never drift.

# The apk feeds a fresh install pulls from. OpenWrt's own snapshot feeds carry the
# base userland (busybox, libc, netifd, ...); our release feeds carry the kernel,
# every kmod, and our add-on packages. The device trusts OpenWrt's key for the
# former and our key for the latter. OWRT_SNAP is overridable so an offline medium
# can point these at a local mirror baked onto the install image.
OWRT_SNAP="${OWRT_SNAP:-https://downloads.openwrt.org/snapshots}"
RWRT_REL="${RWRT_REL:-https://github.com/cmspam/rollingwrt/releases/download}"

# Names used across the disk layout. Kept here so the initramfs gate (which finds
# the LUKS root by content) and the installer agree, and so a future tool can
# recognise a rollingWRT disk by its GPT labels.
RWRT_MAPPER="croot"            # dm-crypt mapper name; MUST match the UKI cmdline rollingwrt.name
RWRT_ESP_LABEL="rwrt-esp"
RWRT_ROOT_LABEL="rwrt-root"    # the LUKS partition
RWRT_DATA_LABEL="rwrt-data"    # optional ZFS data pool partition

# The base set a bootable rollingWRT root needs. Profiles (router/hypervisor/nas)
# add to this. The first two lines are OpenWrt's own x86-64 DEFAULT_PACKAGES
# (include/target.mk + target/linux/x86), copied verbatim so we never drift from
# what an OpenWrt rootfs ships - in particular uclient-fetch (which provides the
# /usr/bin/wget that apk itself execs to download feeds) and libustream-mbedtls
# (uclient-fetch's TLS backend for the https feeds). The third line is what
# rollingWRT adds on top: apk, procd init, the router services, block storage
# tooling, and our kernel + on-device boot stack. Kept as a plain string so the
# installer and the offline-cache builder ask apk for the same set. (OpenWrt's default
# kmod-button-hotplug is intentionally left out: it is a standalone kernel package our
# kernel job does not build, so it would resolve to OpenWrt's stock-kernel build and
# conflict with rollingwrt-kernel; nothing in the base needs it.)
RWRT_BASE_PKGS="${RWRT_BASE_PKGS:-\
base-files ca-bundle dropbear fstools libc libgcc libustream-mbedtls logd mtd \
netifd uci uclient-fetch urandom-seed urngd \
partx-utils mkf2fs e2fsprogs grub2-bios-setup \
apk-mbedtls busybox procd procd-ujail ubox ubus odhcp6c odhcpd-ipv6only dnsmasq \
firewall4 nftables-json blockd mount-utils blkid kmod \
rollingwrt-kernel rollingwrt-boot}"

# ANSI helpers. Quiet if not a tty (piped installs).
if [ -t 1 ]; then C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else C_B=; C_G=; C_Y=; C_R=; C_0=; fi
