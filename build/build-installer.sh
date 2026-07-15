#!/usr/bin/env bash
# Build the rollingWRT INSTALLER IMAGE: a minimal OpenWrt initramfs live image that
# boots in RAM and runs image/rollingwrt-install. It is the shared core of the three
# delivery envelopes (ISO / kexec / bin456789-reinstall). Run AFTER build.sh in the
# same tree (it reuses the toolchain, kernel and already-built packages).
#
# The installer image needs a SEPARATE, minimal package selection, so this swaps
# openwrt/.config to image/installer.config, builds the image, and RESTORES the main
# config + feeds afterwards (else the main tree loses its package selection).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"      # repo/
OUT="${OUT:-$PWD/out}"
OWRT="${OWRT:-$PWD/openwrt}"
FEED="${FEED:-$HERE/feed}"
cd "$OWRT"

echo ">>> installer image: build the outer tools"
./scripts/feeds install gptfdisk dosfstools >/dev/null 2>&1 || true
# sgdisk is a sub-package of gptfdisk and is only produced when selected, so build
# it with the installer config's selection active (done below); here just ensure
# the package trees are present.

echo ">>> installer image: stage the files/ overlay (installer + rootfs + banner)"
rm -rf files; mkdir -p files/usr/bin files/etc
install -m0755 "$HERE/image/rollingwrt-install" files/usr/bin/rollingwrt-install
# embed the base rootfs so the image is self-contained (ISO / kexec / reinstall
# have no second disk to read it from). Pick the NEWEST rootfs across $OUT (the
# release copy build.sh makes) and bin/targets (the raw make output). ls -t sorts
# newest first, so an incremental `make ... target/install` that only refreshed
# bin/targets still wins over a stale $OUT copy from an earlier run.
RFS="$(ls -t "$OUT"/*rootfs.tar.gz bin/targets/x86/64/*rootfs.tar.gz 2>/dev/null | head -1)"
[ -n "$RFS" ] || { echo "ERROR: no rootfs tarball to embed (run build.sh first)"; exit 1; }
echo ">>> installer image: embedding rootfs $RFS"
cp "$RFS" files/rollingwrt-rootfs.tar.gz
cat > files/etc/rc.local <<'RC'
#!/bin/sh
echo; echo "=============================================="
echo " rollingWRT installer"
echo " a base rootfs is bundled at /rollingwrt-rootfs.tar.gz"
echo " run:  rollingwrt-install --disk /dev/sdX --rootfs /rollingwrt-rootfs.tar.gz"
echo "=============================================="; echo
exit 0
RC
chmod +x files/etc/rc.local

echo ">>> installer image: select minimal config + build"
cp .config "$OUT/.config.main.bak"
cp "$HERE/image/installer.config" .config
make defconfig >/dev/null 2>&1
# now sgdisk is selected: (re)build gptfdisk so sgdisk.apk exists, refresh the index
make package/feeds/packages/gptfdisk/compile package/feeds/packages/dosfstools/compile >/dev/null 2>&1 || true
make package/index >/dev/null 2>&1 || true
make package/install target/install
BIN="$OUT/rollingwrt-installer-initramfs-kernel.bin"
cp bin/targets/x86/64/*initramfs-kernel.bin "$BIN"

echo ">>> installer image: wrap the kernel+initramfs as a hybrid ISO"
# grub-mkrescue + the grub BIOS (i386-pc) and UEFI (x86_64-efi) module sets +
# xorriso/mtools, all in the build container, make a BIOS+UEFI bootable,
# USB-writable ISO that grub boots straight into the installer kernel (the
# initramfs is embedded, so no separate initrd is needed).
if command -v grub-mkrescue >/dev/null 2>&1 && command -v xorriso >/dev/null 2>&1; then
	ISOD="$(mktemp -d)"; mkdir -p "$ISOD/boot/grub"
	cp "$BIN" "$ISOD/boot/installer"
	cat > "$ISOD/boot/grub/grub.cfg" <<'CFG'
set timeout=3
set default=0
menuentry "rollingWRT installer" {
	linux /boot/installer console=tty0 console=ttyS0
}
CFG
	if grub-mkrescue -o "$OUT/rollingwrt-installer.iso" "$ISOD" >/dev/null 2>&1; then
		echo ">>> ISO: $OUT/rollingwrt-installer.iso"
	else
		echo ">>> WARNING: ISO build failed (grub modules / xorriso)"
	fi
	rm -rf "$ISOD"
else
	echo ">>> skipping ISO (grub-mkrescue or xorriso not available)"
fi

echo ">>> installer image: restore the main config + feeds"
rm -rf files
./scripts/feeds update rwrt >/dev/null 2>&1 || true
./scripts/feeds install -p rwrt rollingwrt-boot rollingwrt-kernel incus >/dev/null 2>&1 || true
cp "$HERE/config/x86-64.config" .config
make defconfig >/dev/null 2>&1
# the installer config selected a different kernel module set, so switching back
# leaves the main kmods (dax, etc.) unbuilt; rebuild the kernel + modules so the
# main tree can `make package/install target/install` again without errors.
make target/linux/compile >/dev/null 2>&1 || true
rm -f "$OUT/.config.main.bak"

echo ">>> installer image done: $OUT/rollingwrt-installer-initramfs-kernel.bin"
