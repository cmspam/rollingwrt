---
title: Boot and Security
nav_order: 3
has_children: true
permalink: /boot-and-security/
---

# Boot and Security

rollingWRT boots a signed Unified Kernel Image with systemd-boot, optionally from an
encrypted root that the TPM unlocks automatically. This section explains each piece.

## The Unified Kernel Image

A Unified Kernel Image (UKI) is a single signed EFI executable that bundles the kernel,
the initramfs, and the kernel command line. rollingWRT builds the UKI on the machine at
install time and rebuilds it whenever the kernel or its modules change, so the kernel,
its matching modules, and the boot image always move together in one step.

Because the whole image is one signed file, its measurement into the TPM is stable and
predictable, which is what makes the signed-policy TPM unlock below possible. systemd-boot
loads the UKI from the EFI System Partition.

- [Secure Boot](./secure-boot/) - per-machine keys, no shim or vendor key.
- [TPM and LUKS](./tpm-and-luks/) - encrypted root with automatic unlock.
