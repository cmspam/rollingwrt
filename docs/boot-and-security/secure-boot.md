---
title: Secure Boot
parent: Boot and Security
nav_order: 1
permalink: /boot-and-security/secure-boot/
---

# Secure Boot

rollingWRT supports UEFI Secure Boot with **per-machine keys**. There is no shim, no MOK,
and no vendor or central signing key. Each machine generates its own Platform Key, KEK,
and db, and signs its own Unified Kernel Image and systemd-boot loader with them. A key
that signs one machine's boot image is never trusted by another.

This is optional. rollingWRT boots fine with Secure Boot disabled; the signed UKI and the
TPM unlock still work.

## How it is set up

At install time the installer runs `rollingwrt-secureboot enable`, which:

- generates the machine's keys with `sbctl` (kept under `/var/lib/sbctl`, which persists),
- signs the Unified Kernel Image and the systemd-boot loader with the db key, and
- stages the signed key databases in `loader/keys/auto/` on the EFI System Partition and
  sets `secure-boot-enroll force` in `loader.conf`.

Microsoft's db keys are kept alongside the machine's own, so signed option ROMs and other
signed firmware binaries still load.

## Turning it on

Enrollment needs the firmware in **Setup Mode**, the state where it has no Platform Key
and will accept a new set. The install itself does not require Secure Boot, so a machine
that shipped with vendor keys installs and boots normally with Secure Boot off. To turn it
on:

1. Enter the firmware setup once and **clear or erase the Secure Boot keys**. The wording
   varies by vendor ("Erase all Secure Boot keys", "Reset to Setup Mode", "Delete PK").
   This puts the firmware in Setup Mode.
2. Reboot. Because the signed key databases are already staged on the ESP with
   `secure-boot-enroll force`, **systemd-boot enrolls** the Platform Key, KEK, and db
   itself, then boots the signed UKI with Secure Boot enforcing on the machine's own keys.

No shim or MOK enrollment prompt is involved. If you prefer to enroll from a running
system instead of at boot, `rollingwrt-secureboot enroll` writes the keys through the
efivars directly (the firmware must be in Setup Mode).

## Keeping it valid across updates

When the kernel or its modules change, the Unified Kernel Image is rebuilt and re-signed
with the machine's db key (`rollingwrt-secureboot sign`), so Secure Boot keeps accepting
it without any re-enrollment.

## Checking the state

```
rollingwrt-secureboot status
```

reports the machine's key state: whether the keys exist and whether the boot files are
signed with them.

To see whether Secure Boot is actually enforcing on the running system, check the kernel
log, which records what the firmware reported at boot:

```
dmesg | grep -i "secure boot"
```

`Secure boot enabled` means the firmware enrolled the machine's keys and is enforcing them.

## Why per-machine keys

A shared signing key means one leaked key breaks every install. Per-machine keys keep the
trust local: the key never leaves the machine, and there is nothing central to compromise.
The tradeoff is the one-time Setup Mode step above, done per machine.
