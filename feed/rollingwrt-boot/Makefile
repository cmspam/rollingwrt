include $(TOPDIR)/rules.mk

PKG_NAME:=rollingwrt-boot
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_MAINTAINER:=cmspam
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

# compile the PCR-11 predictor (parses the UKI PE, reproduces sd-stub's measure)
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) $(TARGET_LDFLAGS) \
		-o $(PKG_BUILD_DIR)/rollingwrt-pcr11-predict \
		$(PKG_BUILD_DIR)/rollingwrt-pcr11-predict.c -lcrypto
endef

define Package/rollingwrt-boot
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=rollingWRT UKI + LUKS/TPM boot tooling
  # runtime deps for on-device UKI build/sign + TPM unlock
  DEPENDS:=+cryptsetup +tpm2-tools +sbctl +efibootmgr +binutils +zstd \
	+openssl-util +libopenssl +systemd-boot +grub2 \
	+kmod-dm +kmod-tpm +kmod-tpm-tis +kmod-tpm-crb +kmod-crypto-sha256
endef

define Package/rollingwrt-boot/description
  Builds and signs the Unified Kernel Image on the machine and unlocks the LUKS
  root via a signed PCR-11 TPM policy. Because the UKI is rebuilt on every kernel
  or module change, `apk upgrade` moves the kernel + matched kmods and rewrites
  the boot image as one step. Signing is per-machine (no central key).
endef

define Package/rollingwrt-boot/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/lib/rollingwrt $(1)/etc/rollingwrt
	$(INSTALL_BIN) ./files/rollingwrt-uki            $(1)/usr/bin/
	$(INSTALL_BIN) ./files/rollingwrt-mkinitramfs    $(1)/usr/bin/
	$(INSTALL_BIN) ./files/rollingwrt-tpm-enroll     $(1)/usr/bin/
	$(INSTALL_BIN) ./files/rollingwrt-tpm-unenroll   $(1)/usr/bin/
	$(INSTALL_BIN) ./files/rollingwrt-tpm-sign-policy $(1)/usr/bin/
	$(INSTALL_BIN) ./files/rollingwrt-tpm-unseal     $(1)/usr/bin/
	$(INSTALL_BIN) ./files/rollingwrt-grub-install   $(1)/usr/bin/
	$(INSTALL_BIN) ./files/rollingwrt-secureboot     $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/rollingwrt-pcr11-predict $(1)/usr/bin/
	$(INSTALL_BIN) ./files/init                      $(1)/usr/lib/rollingwrt/init
	# grub BIOS boot blocks for the legacy-BIOS install path. OpenWrt does not ship
	# grub-install (only grub-bios-setup), and the i386-pc modules are not in the
	# rootfs; but the grub2 package builds a self-contained core image (fat + part_gpt
	# + linux baked in, prefix /boot/grub, early config = configfile (hd0,gpt1)/boot/
	# grub/grub.cfg) plus the MBR boot.img into STAGING_DIR_IMAGE. Ship those two and
	# rollingwrt-grub-install writes them with grub-bios-setup. grub2 is a DEPENDS, so
	# it installs (and populates STAGING_DIR_IMAGE) before this package.
	$(INSTALL_DIR) $(1)/usr/lib/rollingwrt/grub
	$(CP) $(STAGING_DIR_IMAGE)/grub2/boot.img     $(1)/usr/lib/rollingwrt/grub/boot.img
	$(CP) $(STAGING_DIR_IMAGE)/grub2/gpt-core.img $(1)/usr/lib/rollingwrt/grub/core.img
endef

# Rebuild + re-sign the UKI whenever the kernel or its modules change. apk-tools 3
# fires this trigger ONCE at the end of the transaction, after the kernel AND all
# kmods are laid down (a plain postinst would run before kmods unpack and the
# initramfs would miss them).
define Package/rollingwrt-boot/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ -f /etc/rollingwrt/uki.conf ] && rollingwrt-uki || true
exit 0
endef

PKG_TRIGGERS:=/lib/modules /boot

$(eval $(call BuildPackage,rollingwrt-boot))
