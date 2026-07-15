---
title: Installation
nav_order: 2
permalink: /getting-started/
---

# Installation

rollingWRT installs from a live ISO. The ISO is a boot vehicle only: it carries the
`rollingwrt-install` script, a static `apk`, and the feed keys, and installs the system
onto a disk from the apk feeds. The current installer supports **UEFI systems only**;
it refuses to run under legacy BIOS.

## 1. Get the ISO

Download the latest ISO from the [installer
release](https://github.com/cmspam/rollingwrt/releases/tag/installer) and write it to a
USB stick, or attach it to a virtual machine. The ISO boots under UEFI with or without
Secure Boot.

## 2. Boot it and run the installer

Boot the target from the ISO. Log in as `root`, then run:

```
rollingwrt-install
```

The installer asks a short series of questions:

- **Disk.** Which disk to install to.
- **Layout.** Use the whole disk, use the whole disk but leave free space at the end,
  install into existing free space, or point at existing ESP and root partitions.
- **Profile.** The package set to install:
  - `minimal` - the base system only.
  - `router` - the OpenWrt network stack.
  - `nas` - ZFS and file sharing.
  - `hypervisor` - Incus, QEMU, and ZFS (the default).
- **Encryption.** Whether to encrypt the root with LUKS and TPM auto-unlock (default
  yes). If you enable it, you set a recovery passphrase. Keep this passphrase: it is the
  only way in if the hardware changes.
- **Hostname**, and an **admin SSH key** (`github:USER`, `gitlab:USER`, `@file`, or a
  pasted key) or a root password.
- Optional: a **serial console** (off by default, since forcing `console=ttyS0` prevents
  some hardware from booting) and any **extra kernel arguments**.

It then partitions the disk, installs the system with apk, builds and signs a Unified
Kernel Image on the machine, and (if encryption was chosen) seals the LUKS key to the
TPM. When it finishes, remove the install medium and reboot.

## 3. First boot

On an encrypted install the root unlocks automatically through a signed PCR-11 TPM
policy, with the recovery passphrase as a fallback if the measurement does not match.
The first boot after install is OpenWrt's normal firstboot.

## Secure Boot

If the firmware is in Secure Boot User Mode, enter the firmware once and clear or erase
the Secure Boot keys to put it in Setup Mode. The next boot enrolls rollingWRT's own
keys automatically. There is no central signing key; each machine signs its own UKI.
