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

# The minimal OpenWrt base a bootable rollingWRT root needs, plus our boot stack.
# Profiles (router/hypervisor/nas) add to this. Kept as a plain string so the
# installer and the offline-cache builder ask apk for the same set.
RWRT_BASE_PKGS="${RWRT_BASE_PKGS:-base-files busybox libc ca-bundle apk-mbedtls \
procd procd-ujail ubox ubus uci netifd odhcp6c odhcpd-ipv6only dnsmasq \
dropbear firewall4 nftables-json fstools blockd kmod mount-utils \
e2fsprogs blkid rollingwrt-kernel rollingwrt-boot}"

# ANSI helpers. Quiet if not a tty (piped installs).
if [ -t 1 ]; then C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else C_B=; C_G=; C_Y=; C_R=; C_0=; fi
