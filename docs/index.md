---
title: Home
nav_order: 1
permalink: /
---

# rollingWRT

rollingWRT is a distribution of [OpenWrt](https://openwrt.org/) for x86-64 machines. It
uses OpenWrt's snapshot kernel, package feeds, and userland, and adds a disk install with
full-system rolling updates, an encrypted root that unlocks with the TPM, and a container
and virtual-machine stack.

It is not an official or supported OpenWrt release.

## How it differs from OpenWrt

### Rolling updates, no reflash

Stock OpenWrt is image-based. You upgrade by flashing a new firmware image with
`sysupgrade`, and the running system is a read-only squashfs with a small writable
overlay. rollingWRT installs onto an ordinary read-write disk and updates the whole
system, kernel included, with apk:

```
apk update && apk upgrade
```

The base userland comes from OpenWrt's own feeds; the kernel, every kernel module, and
the add-on packages come from rollingWRT's feed. There is no image to build or flash and
no need to wipe the system to move forward. The kernel is itself an apk package, so
installing a newer one rebuilds and re-signs the boot image in the same step.

### Signed boot, encryption, and TPM auto-unlock

On a UEFI install, rollingWRT builds a signed [Unified Kernel Image](./boot-and-security/)
on the machine and boots it with systemd-boot. The root filesystem is LUKS2-encrypted and
unlocks automatically through a TPM policy that is re-signed on every kernel update, so
updates never break unlocking. A recovery passphrase is the fallback. Secure Boot is
supported with per-machine keys and no shim or vendor key. Legacy BIOS machines are also
supported: they boot GRUB from the MBR and unlock an encrypted root by passphrase (BIOS
has no Secure Boot or measured-boot TPM). See [Boot and Security](./boot-and-security/).

### A persistent disk system

Because rollingWRT is a disk system rather than a flash appliance, `/var` is a real
directory on the encrypted root (stock OpenWrt keeps it on tmpfs, wiped every boot). This
lets Incus, ZFS, and service state under `/var/lib` survive reboots.

### Additional packages

rollingWRT builds and hosts its own kernel because stock OpenWrt disables `KVM_IOAPIC`
(needed for an in-kernel irqchip) and cannot add the Intel Xe DRM stack out of tree. It
builds every kernel module against that kernel. On top of the kernel it adds Incus
(system containers and virtual machines), QEMU with KVM, ZFS, and the on-device boot
tooling (tpm2-tools, sbctl, systemd-boot, and the UKI builder).

## Documentation

- [Installation](./getting-started/) - writing the ISO, running the installer, and first
  boot.
- [Boot and Security](./boot-and-security/) - Secure Boot, the Unified Kernel Image, and
  TPM/LUKS auto-unlock.
- [Virtualization with Incus](./virtualization/) - networking a container or VM, and what
  to do after installing VM support.
