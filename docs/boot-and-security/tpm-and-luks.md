---
title: TPM and LUKS
parent: Boot and Security
nav_order: 2
permalink: /boot-and-security/tpm-and-luks/
---

# TPM and LUKS

If you choose encryption during install, rollingWRT puts the root filesystem on LUKS2 and
seals the encryption key to the machine's TPM so it unlocks automatically at boot. A
recovery passphrase is always kept as a fallback.

## How the automatic unlock works

The naive way to bind a LUKS key to a TPM is to seal it against a fixed set of PCR values
(the measurements the firmware and bootloader record). That breaks every time you update
the kernel, because the measurement changes and you have to re-enroll by hand.

rollingWRT avoids that. It seals the key under a **signed policy** (TPM PolicyAuthorize):
the seal trusts a signing key that belongs to the machine, not a frozen PCR value. What
gets measured is the Unified Kernel Image, into PCR 11. On every kernel or module change,
the UKI is rebuilt and rollingWRT signs a fresh PCR-11 policy for the new image and writes
it to the ESP. The unlock then works against the new image without any re-enrollment.

If the boot image is tampered with, PCR 11 takes a value that has no valid signature, the
TPM refuses to release the key, and boot falls back to the recovery passphrase.

## Registering (enrolling) the TPM

Enrollment happens automatically at install time when you enable encryption. You do not
need to run anything by hand for the normal case.

You would re-enroll in a few situations: you moved the disk to different hardware (a
different TPM cannot unseal the old key), you cleared the TPM, or you want to rotate the
sealed key. The command reads the recovery passphrase from standard input, so pipe it in:

```
printf '%s' 'your-recovery-passphrase' | rollingwrt-tpm-enroll /dev/<root-partition>
```

It seals a fresh key to the current TPM, adds it to a LUKS keyslot, and signs the PCR-11
policy for the current UKI. Running it again replaces the previous enrollment rather than
stacking keyslots. To remove TPM unlock entirely and go back to passphrase-only, use
`rollingwrt-tpm-unenroll`.

## The recovery passphrase

The passphrase you set during install is an ordinary LUKS keyslot. Keep it. It is the
only way in if the TPM cannot unseal the key, for example after a hardware change or a
firmware reset. At the unlock prompt, entering it boots the system normally.

## Requirements

Automatic unlock needs a TPM 2.0 (a discrete chip or firmware TPM such as AMD fTPM or
Intel PTT) and a UEFI system. Encryption itself works without a TPM; you just unlock with
the passphrase every boot.
