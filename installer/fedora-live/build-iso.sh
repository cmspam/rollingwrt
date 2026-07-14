#!/usr/bin/env bash
# Build the rollingWRT installer ISO.
#
# The ISO is only a delivery vehicle: a small live Fedora environment whose sole
# job is to boot (under Secure Boot on stock firmware, thanks to Fedora's signed
# shim + grub2), expose /dev/tpmrm0, and run `rollingwrt-install`. The installer
# is distribution independent: it partitions the target, lays down the OpenWrt
# based rollingWRT system with apk, and runs the boot ceremony (UKI, Secure Boot
# keys, TPM seal) inside a chroot of the target using the target's own tools. So
# the live OS never touches the ceremony and can be any distribution; Fedora is
# chosen because its signed boot chain boots under factory Secure Boot.
#
# Pipeline (mirrors cache22's installer ISO):
#   1. dnf --installroot a minimal Fedora rootfs
#   2. stage rollingwrt-install + apk (Alpine's static apk-tools 3) + feed keys
#   3. autologin root on tty1 with a banner
#   4. dracut --add dmsquash-live -> initramfs; mksquashfs the rootfs
#   5. pull vmlinuz / shim / grub2 out of the rootfs
#   6. xorrisofs a hybrid ISO (BIOS + UEFI, Secure Boot bootable)
#
# Must run as root, on Fedora (host or fedora:44 container).
#
# Usage:  ./build-iso.sh [output_dir]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INST="$(cd "$HERE/.." && pwd)"
OUT="${1:-$HERE/out}"
WORK="${HERE}/work"
ROOTFS="$WORK/rootfs"
ISOROOT="$WORK/isoroot"
FEDORA_REL="${FEDORA_REL:-44}"
ISO_DATE="$(date -u --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
ISO_LABEL="ROLLINGWRT_INSTALL"
ISO_NAME="rollingwrt-installer-${ISO_DATE}"

# feed key sources: OpenWrt's snapshot key is committed (no stable URL upstream);
# ours is fetched from our release. Both land in the live env's /etc/apk/keys so
# rollingwrt-install trusts the base feeds and our feed when it apks the target.
RWRT_PUBKEY_URL="${PUBKEY_URL:-https://github.com/cmspam/rollingwrt/releases/download/snapshot/public-key.pem}"

[[ ${EUID} -eq 0 ]] || { echo "build-iso.sh must run as root."; exit 1; }
for tool in dnf dracut mksquashfs xorriso mkfs.fat mcopy mmd curl grub2-mkimage; do
	command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool"; exit 1; }
done
ISOHDPFX="/usr/share/syslinux/isohdpfx.bin"
GRUB_PC_DIR="/usr/lib/grub/i386-pc"
[[ -f "$ISOHDPFX" ]] || { echo "ERROR: missing $ISOHDPFX (install syslinux)"; exit 1; }
[[ -d "$GRUB_PC_DIR" ]] || { echo "ERROR: missing $GRUB_PC_DIR (install grub2-pc-modules)"; exit 1; }

# ─── 1. Bootstrap minimal Fedora rootfs ───────────────────────────
echo "==> Bootstrapping Fedora ${FEDORA_REL} rootfs at $ROOTFS"
rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"

# Only what the installer + live boot chain need. The installed rollingWRT is
# OpenWrt, laid down with apk, so no dnf userland leaks into the target.
PKGS=(
	# live-ISO boot chain: Fedora's MS-signed shim + signed grub2 boot the live
	# env under factory Secure Boot. The installed system's own boot (sd-boot +
	# UKI) is built by rollingwrt-install inside the target chroot, not here.
	kernel-core kernel-modules-core kernel-modules-extra
	shim-x64 grub2-efi-x64 grub2-tools-minimal efibootmgr
	# initramfs + live media (dmsquash-live mounts the squashfs from CD/USB)
	dracut dracut-live dracut-network dracut-config-generic
	# firmware for real wired NICs on install targets
	linux-firmware
	# networking for a network install and fetching our feed
	NetworkManager iproute iputils curl ca-certificates
	openssh-clients openssh-server
	# core userspace
	bash coreutils util-linux util-linux-core findutils grep sed gawk
	less vim-minimal nano which
	glibc-langpack-en sudo systemd systemd-resolved
	# storage / crypto tools rollingwrt-install requires (gdisk = sgdisk)
	parted gdisk e2fsprogs dosfstools cryptsetup lvm2
	# openssl for the TPM policy key rollingwrt-install generates on the host side
	openssl
	# tpm2-tools for eyeballing the TPM from the live env (the seal itself runs in
	# the target chroot with the target's tpm2-tools)
	tpm2-tools
)

dnf install --installroot="$ROOTFS" --use-host-config --releasever="$FEDORA_REL" \
	--setopt=install_weak_deps=False --setopt=keepcache=False \
	--setopt=tsflags=nodocs --assumeyes --nogpgcheck filesystem

mkdir -p "$ROOTFS"/{proc,sys,dev,run}
mount --rbind /proc "$ROOTFS/proc"
mount --rbind /sys  "$ROOTFS/sys"
mount --rbind /dev  "$ROOTFS/dev"
trap 'for m in run dev sys proc; do umount -lR "$ROOTFS/$m" 2>/dev/null || true; done' EXIT

dnf install --installroot="$ROOTFS" --use-host-config --releasever="$FEDORA_REL" \
	--setopt=install_weak_deps=False --setopt=keepcache=False \
	--setopt=tsflags=nodocs --assumeyes --nogpgcheck "${PKGS[@]}"

# ─── 2. Stage the installer, apk, and feed keys ───────────────────
echo "==> Staging rollingwrt-install + apk + feed keys"
install -Dm0755 "$INST/rollingwrt-install"    "$ROOTFS/usr/bin/rollingwrt-install"
install -Dm0644 "$INST/rollingwrt-common.sh"  "$ROOTFS/usr/bin/rollingwrt-common.sh"

# apk: Alpine's static apk-tools 3 binary runs anywhere and speaks the same apk v3
# format OpenWrt uses, so the installer can lay down the OpenWrt target from Fedora.
echo "    fetching Alpine static apk (apk-tools 3)"
ABR="$(curl -sfL https://dl-cdn.alpinelinux.org/alpine/ | grep -oE 'v3\.[0-9]+/' | sort -V | tail -1 | tr -d /)"
AFILE="$(curl -sfL "https://dl-cdn.alpinelinux.org/alpine/$ABR/main/x86_64/" | grep -oE 'apk-tools-static-[0-9][^"]*\.apk' | head -1)"
[[ -n "$AFILE" ]] || { echo "ERROR: cannot find apk-tools-static on Alpine $ABR"; exit 1; }
curl -sfL "https://dl-cdn.alpinelinux.org/alpine/$ABR/main/x86_64/$AFILE" \
	| tar -xzO sbin/apk.static > "$ROOTFS/usr/bin/apk"
chmod 0755 "$ROOTFS/usr/bin/apk"
chroot "$ROOTFS" /usr/bin/apk --version | head -1

# feed keys the installer trusts when it apks the target
mkdir -p "$ROOTFS/etc/apk/keys"
install -m0644 "$INST/keys/openwrt-snapshots.pem" "$ROOTFS/etc/apk/keys/openwrt-snapshots.pem"
if curl -sfL "$RWRT_PUBKEY_URL" -o "$ROOTFS/etc/apk/keys/rollingwrt.pem"; then
	echo "    staged our feed key"
else
	echo "    WARN: could not fetch our feed key ($RWRT_PUBKEY_URL); install will need it at run time" >&2
	rm -f "$ROOTFS/etc/apk/keys/rollingwrt.pem"
fi

# ─── 3. Live env config (autologin root + banner) ─────────────────
echo "==> Configuring live env (autologin, banner)"
echo 'root:rollingwrt' | chroot "$ROOTFS" chpasswd

mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root - $TERM
EOF
cat > "$ROOTFS/root/.bash_profile" <<'EOF'
[[ -f /etc/motd ]] && cat /etc/motd
EOF
chroot "$ROOTFS" systemctl enable NetworkManager.service sshd.service >/dev/null 2>&1 || true

rm -f "$ROOTFS/etc/os-release" "$ROOTFS/usr/lib/os-release"
cat > "$ROOTFS/usr/lib/os-release" <<EOF
NAME="rollingWRT Installer"
PRETTY_NAME="rollingWRT Installer"
ID=rollingwrt-installer
ID_LIKE=fedora
VERSION="${FEDORA_REL} (Live)"
VERSION_ID="${FEDORA_REL}"
HOME_URL="https://github.com/cmspam/rollingwrt"
BUG_REPORT_URL="https://github.com/cmspam/rollingwrt/issues"
EOF
ln -sf ../usr/lib/os-release "$ROOTFS/etc/os-release"

cat > "$ROOTFS/etc/issue" <<'EOF'

  rollingWRT Installer  (live environment; nothing is installed yet)

  tty1 is logged in as root. Run:  rollingwrt-install

EOF
cp "$ROOTFS/etc/issue" "$ROOTFS/etc/issue.net"
cat > "$ROOTFS/etc/motd" <<'EOF'

  rollingWRT installer.  This is a live environment, nothing is installed yet.
  Run:  rollingwrt-install
  It asks a few questions, then installs rollingWRT to a disk you choose.

EOF
echo "rollingwrt-live" > "$ROOTFS/etc/hostname"

[[ -f "$ROOTFS/etc/selinux/config" ]] && \
	sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$ROOTFS/etc/selinux/config"
chroot "$ROOTFS" systemctl mask plymouth-start.service plymouth-quit.service \
	plymouth-quit-wait.service plymouth-read-write.service >/dev/null 2>&1 || true
rm -f "$ROOTFS/etc/resolv.conf"

# ─── 4. Build initramfs (dmsquash-live) ───────────────────────────
echo "==> Building initramfs via dracut --add dmsquash-live"
KVER=$(basename "$(ls -d "$ROOTFS"/usr/lib/modules/*/ | head -1)")
[[ -n "$KVER" ]] || { echo "ERROR: no kernel found in $ROOTFS/usr/lib/modules/"; exit 1; }
echo "    kernel version: $KVER"
chroot "$ROOTFS" dracut --no-hostonly --add 'dmsquash-live' \
	--add-drivers 'squashfs overlay loop dm_mod sr_mod sd_mod ahci nvme xhci_hcd xhci_pci uhci_hcd ehci_hcd ehci_pci usb_storage virtio_blk virtio_net virtio_pci virtio_scsi tpm_crb tpm_tis e1000 e1000e r8169 igb igc ixgbe tg3' \
	--reproducible --kver "$KVER" --force "/boot/initramfs-${KVER}.img"

# ─── 5. Pull boot artifacts out, then squashfs the rootfs ─────────
echo "==> Extracting boot artifacts"
mkdir -p "$WORK/boot"
cp "$ROOTFS/usr/lib/modules/${KVER}/vmlinuz"  "$WORK/boot/vmlinuz"
cp "$ROOTFS/boot/initramfs-${KVER}.img"       "$WORK/boot/initramfs.img"
cp "$ROOTFS/boot/efi/EFI/fedora/shimx64.efi"  "$WORK/boot/shimx64.efi" 2>/dev/null \
	|| cp "$ROOTFS"/usr/lib/efi/shim/*/EFI/fedora/shimx64.efi "$WORK/boot/shimx64.efi"
cp "$ROOTFS/boot/efi/EFI/fedora/mmx64.efi"    "$WORK/boot/mmx64.efi" 2>/dev/null \
	|| cp "$ROOTFS"/usr/lib/efi/shim/*/EFI/fedora/mmx64.efi "$WORK/boot/mmx64.efi"
cp "$ROOTFS/boot/efi/EFI/fedora/grubx64.efi"  "$WORK/boot/grubx64.efi" 2>/dev/null \
	|| cp "$ROOTFS"/usr/lib/efi/grub2/*/EFI/fedora/grubx64.efi "$WORK/boot/grubx64.efi"
for f in vmlinuz initramfs.img shimx64.efi mmx64.efi grubx64.efi; do
	[[ -f "$WORK/boot/$f" ]] || { echo "ERROR: missing $WORK/boot/$f"; exit 1; }
done

for m in run dev sys proc; do umount -lR "$ROOTFS/$m" 2>/dev/null || true; done
trap - EXIT
rm -rf "$ROOTFS/var/cache/dnf"/* "$ROOTFS/var/log"/* "$ROOTFS/var/tmp"/* "$ROOTFS/tmp"/*

echo "==> Building LiveOS/rootfs.img and squashing it"
SQUASH_WORK=$(mktemp -d)
mkdir -p "$SQUASH_WORK/LiveOS"
ROOTFS_MB=$(( ($(du -sk "$ROOTFS" | awk '{print $1}') / 1024) + 256 ))
truncate -s "${ROOTFS_MB}M" "$SQUASH_WORK/LiveOS/rootfs.img"
mkfs.ext4 -L rootfs -F "$SQUASH_WORK/LiveOS/rootfs.img" >/dev/null
ROOTFS_MNT=$(mktemp -d)
mount -o loop "$SQUASH_WORK/LiveOS/rootfs.img" "$ROOTFS_MNT"
cp -a "$ROOTFS"/. "$ROOTFS_MNT/"
umount "$ROOTFS_MNT"; rmdir "$ROOTFS_MNT"
mkdir -p "$ISOROOT/LiveOS"
mksquashfs "$SQUASH_WORK" "$ISOROOT/LiveOS/squashfs.img" \
	-comp zstd -Xcompression-level 19 -b 1M -no-xattrs -noappend
rm -rf "$SQUASH_WORK"
ls -lh "$ISOROOT/LiveOS/squashfs.img"

# ─── 6. Assemble + xorriso the hybrid ISO ─────────────────────────
echo "==> Assembling ISO tree"
mkdir -p "$ISOROOT/images" "$ISOROOT/EFI/BOOT" "$ISOROOT/EFI/fedora" "$ISOROOT/grub" \
	"$ISOROOT/boot/grub/i386-pc"
cp "$WORK/boot/vmlinuz"       "$ISOROOT/images/vmlinuz"
cp "$WORK/boot/initramfs.img" "$ISOROOT/images/initramfs.img"
cp "$WORK/boot/shimx64.efi"   "$ISOROOT/EFI/BOOT/BOOTX64.EFI"
cp "$WORK/boot/grubx64.efi"   "$ISOROOT/EFI/BOOT/grubx64.efi"
cp "$WORK/boot/mmx64.efi"     "$ISOROOT/EFI/BOOT/mmx64.efi"

cat > "$ISOROOT/EFI/fedora/grub.cfg" <<EOF
set timeout=3
set default=0
search --no-floppy --set=root --label ${ISO_LABEL}
menuentry 'rollingWRT Installer (live)' {
    linuxefi /images/vmlinuz root=live:CDLABEL=${ISO_LABEL} rd.live.image selinux=0 enforcing=0 audit=0 quiet rd.plymouth=0 plymouth.enable=0
    initrdefi /images/initramfs.img
}
menuentry 'rollingWRT Installer (live, troubleshoot - rd.shell)' {
    linuxefi /images/vmlinuz root=live:CDLABEL=${ISO_LABEL} rd.live.image selinux=0 enforcing=0 audit=0 console=tty0 console=ttyS0,115200 rd.shell rd.debug plymouth.enable=0
    initrdefi /images/initramfs.img
}
EOF
cp "$ISOROOT/EFI/fedora/grub.cfg" "$ISOROOT/grub/grub.cfg"

cat > "$ISOROOT/boot/grub/grub.cfg" <<EOF
set timeout=3
set default=0
search --no-floppy --set=root --label ${ISO_LABEL}
menuentry 'rollingWRT Installer (live)' {
    linux /images/vmlinuz root=live:CDLABEL=${ISO_LABEL} rd.live.image selinux=0 enforcing=0 audit=0 quiet rd.plymouth=0 plymouth.enable=0
    initrd /images/initramfs.img
}
menuentry 'rollingWRT Installer (live, troubleshoot - rd.shell)' {
    linux /images/vmlinuz root=live:CDLABEL=${ISO_LABEL} rd.live.image selinux=0 enforcing=0 audit=0 console=tty0 console=ttyS0,115200 rd.shell rd.debug plymouth.enable=0
    initrd /images/initramfs.img
}
EOF

echo "==> Building BIOS eltorito image"
grub2-mkimage --format=i386-pc-eltorito --output="$ISOROOT/boot/grub/i386-pc/eltorito.img" \
	--prefix=/boot/grub iso9660 biosdisk normal configfile linux echo ls cat \
	search search_label part_msdos part_gpt
cp "$GRUB_PC_DIR/cdboot.img" "$ISOROOT/boot/grub/i386-pc/"

echo "==> Building EFI boot image"
EFIIMG="$WORK/efiboot.img"
EFI_SIZE_KB=$(du -bcs "$ISOROOT/EFI" | tail -1 | awk \
	'function ceil(x){return int(x)+(x>int(x))}
	 { kib=$1/1024; print int( ((ceil(kib/1024)*1024) + 8192) ) }')
MKFS_OPTS=(-C -n RWRTEFI)
(( EFI_SIZE_KB >= 36864 )) && MKFS_OPTS+=(-F 32)
rm -f "$EFIIMG"
mkfs.fat "${MKFS_OPTS[@]}" "$EFIIMG" "$EFI_SIZE_KB" >/dev/null
mmd -i "$EFIIMG" ::/EFI ::/EFI/BOOT ::/EFI/fedora
mcopy -i "$EFIIMG" -s "$ISOROOT/EFI"/* ::/EFI/

echo "==> xorrisofs"
mkdir -p "$OUT"
FINAL_ISO="$OUT/${ISO_NAME}.iso"
xorriso -as mkisofs \
	-iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
	-volid "$ISO_LABEL" -appid 'rollingwrt-installer' \
	-publisher 'rollingWRT <https://github.com/cmspam/rollingwrt>' \
	-preparer 'rollingWRT build pipeline' \
	-partition_offset 16 -isohybrid-mbr "$ISOHDPFX" \
	-b boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table \
	-appended_part_as_gpt \
	-append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$EFIIMG" \
	-iso_mbr_part_type EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 \
	-eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot \
	-eltorito-catalog 'boot/grub/boot.cat' \
	-o "$FINAL_ISO" "$ISOROOT"

ls -lh "$FINAL_ISO"; sha256sum "$FINAL_ISO"
echo "==> Done. ISO at $FINAL_ISO"
