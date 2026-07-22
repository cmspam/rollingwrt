# rollingWRT ESP mount helper (sourced by rollingwrt-uki and rollingwrt-grub-install).
#
# By design the ESP is not kept mounted while the system runs, so the boot-image
# writers mount it themselves. There is a catch: the initramfs unlock gate mounts
# the ESP read-only during boot and switch_root then detaches that mount, leaving
# the FAT superblock pinned read-only (it is in no mount namespace, yet the kernel
# still holds it). A direct read-write mount then fails with EBUSY ("would change RO
# state"), because it would be a second, conflicting instance of the same superblock.
#
# The reliable path is to mount the ESP read-only first (that shares the pinned
# superblock, or mounts cleanly if there is none) and then remount it read-write in
# place. A remount changes the flags of the existing mount, so it never creates a
# conflicting instance. On release we remount read-only and unmount.
#
# Needs $ESP set. Uses $ESP_LABEL (FAT volume label, default rwrt-esp), then
# $ESP_DISK + $ESP_PART (our fixed layout: the ESP is partition 1) as a fallback.

RWRT_ESP_MOUNTED=0

esp_find(){
	# by filesystem label first (blkid -L works with no udev / no by-label symlinks)
	dev="$(blkid -L "${ESP_LABEL:-rwrt-esp}" 2>/dev/null || true)"
	if [ -z "$dev" ] || [ ! -b "$dev" ]; then
		# fall back to partition 1 of the ESP disk (nvme/mmc take a 'p' separator)
		dev=""
		case "${ESP_DISK:-}" in
			"") : ;;
			*[0-9]) dev="${ESP_DISK}p${ESP_PART:-1}" ;;
			*)      dev="${ESP_DISK}${ESP_PART:-1}" ;;
		esac
	fi
	[ -n "$dev" ] && [ -b "$dev" ] && echo "$dev"
}

esp_mount(){
	# already mounted (install-time chroot, or a user mounted it): just make it writable
	if mountpoint -q "$ESP" 2>/dev/null; then
		mount -o remount,rw "$ESP" 2>/dev/null || true
		return 0
	fi
	mkdir -p "$ESP"
	_dev="$(esp_find)"
	[ -n "$_dev" ] || { echo "rollingwrt: ESP not found (label ${ESP_LABEL:-rwrt-esp}, disk ${ESP_DISK:-?})" >&2; return 1; }
	# Mount read-only first (compatible with the gate's pinned read-only superblock),
	# then remount read-write in place so there is no conflicting second instance. If the
	# read-only mount fails - a leftover read-write orphan makes it "change RO state" -
	# mount read-write directly (which then matches that orphan's state).
	if mount -t vfat -o ro "$_dev" "$ESP" 2>/dev/null; then
		RWRT_ESP_MOUNTED=1
		mount -o remount,rw "$ESP" || {
			echo "rollingwrt: cannot remount ESP $ESP read-write" >&2
			umount "$ESP" 2>/dev/null || true; RWRT_ESP_MOUNTED=0; return 1; }
	elif mount -t vfat -o rw "$_dev" "$ESP" 2>/dev/null; then
		RWRT_ESP_MOUNTED=1
	else
		echo "rollingwrt: cannot mount ESP $_dev at $ESP" >&2; return 1
	fi
}

esp_umount(){
	[ "$RWRT_ESP_MOUNTED" = 1 ] || return 0
	sync
	mount -o remount,ro "$ESP" 2>/dev/null || true
	umount "$ESP" 2>/dev/null || true
	RWRT_ESP_MOUNTED=0
}
