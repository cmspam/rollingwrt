---
title: Installation
nav_order: 2
permalink: /getting-started/
---

# Installation

rollingWRT installs from a live ISO. The ISO is a boot vehicle only: it carries the
`rollingwrt-install` script, a static `apk`, and the feed keys, and installs the system
onto a disk from the apk feeds. It installs on both **UEFI** and **legacy BIOS**
machines; the installer detects which and sets up the matching boot path:

- **UEFI** gets a signed Unified Kernel Image booted by systemd-boot, optional Secure
  Boot with per-machine keys, and (if you encrypt) automatic TPM unlock.
- **BIOS** gets GRUB in the MBR loading the kernel and unlock initramfs from a FAT
  partition. BIOS firmware has no Secure Boot or measured-boot TPM, so those do not
  apply; an encrypted BIOS install unlocks with a passphrase entered at each boot. A
  BIOS install uses the whole disk.

## 1. Get the ISO

Download the latest ISO from the [installer
release](https://github.com/cmspam/rollingwrt/releases/tag/installer) and write it to a
USB stick, or attach it to a virtual machine. The ISO boots under UEFI (with or without
Secure Boot) and under legacy BIOS.

## 2. Boot it and run the installer

Boot the target from the ISO. Log in as `root`, then run:

```
rollingwrt-install
```

The installer presents a menu you navigate, rather than a fixed list of questions. Each
row shows its current value; select a row to change it, then choose **Install**. When no
terminal or `dialog` is available it falls back to a plain text wizard that asks the same
things in order.

- **Disk.** Which disk to install to.
- **Layout.** Use the whole disk, use the whole disk but leave free space at the end,
  install into existing free space, or point at existing ESP and root partitions. (On
  BIOS only the whole-disk options are offered, because GRUB's boot image dictates the
  partition layout.)
- **Features.** A checklist you toggle on and off. The base system is always a working
  OpenWrt router with the LuCI web interface; on top of it you enable any combination of:
  - **Virtualization** - Incus (system containers and VMs) plus QEMU/KVM, with the Incus
    web UI wired into LuCI.
  - **ZFS** - ZFS storage pool support.
  - **File sharing** - a Samba (SMB/CIFS) server, with its LuCI page.

  They are independent, so a single box can be, for example, both a hypervisor and a file
  server. Each role also installs its LuCI app, so it is manageable from the web UI.
- **Extra packages.** Any additional apk packages to install on top of the features
  (space-separated, from OpenWrt's feeds or rollingWRT's), or blank for none.
- **Encryption.** Whether to encrypt the root with LUKS (default yes) and a passphrase
  you set. On UEFI the key is also sealed to the TPM for automatic unlock, and the
  passphrase is the fallback; keep it, as it is the only way in if the hardware changes.
  On BIOS there is no TPM measured boot, so you enter the passphrase at every boot.
- **Hostname**, and **admin access**: an **SSH key** (`github:USER`, `gitlab:USER`,
  `@file`, or a pasted key) and/or a **root password**, set independently. At least one
  is required. The root password is what the console login prompts for.
- Optional: a **serial console** (off by default, since forcing `console=ttyS0` prevents
  some hardware from booting) and any **extra kernel arguments**.

It then partitions the disk and installs the system with apk. On UEFI it builds and
signs a Unified Kernel Image and installs systemd-boot; on BIOS it installs GRUB into
the MBR with the kernel and unlock initramfs on the FAT partition. If encryption was
chosen, a UEFI install also seals the LUKS key to the TPM. When it finishes, remove the
install medium and reboot.

## 3. First boot

On an encrypted **UEFI** install the root unlocks automatically through a signed PCR-11
TPM policy, with the passphrase as a fallback if the measurement does not match. On an
encrypted **BIOS** install you enter the passphrase at each boot. The first boot after
install is OpenWrt's normal firstboot.

## Secure Boot (UEFI only)

If the firmware is in Secure Boot User Mode, enter the firmware once and clear or erase
the Secure Boot keys to put it in Setup Mode. The next boot enrolls rollingWRT's own
keys automatically. There is no central signing key; each machine signs its own UKI.
BIOS machines have no Secure Boot.
