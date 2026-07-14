include $(TOPDIR)/rules.mk

PKG_NAME:=qemu-firmware-edk2
PKG_VERSION:=202605
PKG_RELEASE:=2
PKG_MAINTAINER:=cmspam
PKG_LICENSE:=BSD-2-Clause-Patent

include $(INCLUDE_DIR)/package.mk

define Package/qemu-firmware-edk2
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=EDK2/OVMF UEFI firmware for qemu (Incus VMs)
  URL:=https://github.com/tianocore/edk2
endef

define Package/qemu-firmware-edk2/description
  Prebuilt OVMF (EDK2) UEFI firmware for x86-64 qemu guests, laid out the way incus
  locates firmware (its edk2 driver looks under /usr/share/OVMF by name). OVMF_CODE.fd
  is built from tianocore edk2-stable202605 with the Zabbly/Incus patches and a
  rollingWRT boot logo. There are TWO variable stores because incus pairs a specific
  vars file per usage: OVMF_VARS.fd is the empty (Setup Mode, no keys) store used for
  security.secureboot=false - without an empty store, unsigned guest images are
  rejected; OVMF_VARS.ms.fd carries the Microsoft Secure Boot keys and is used for
  security.secureboot=true. The blobs are prebuilt (edk2's build system is heavy);
  rebuild only when edk2 changes materially.
endef

# The firmware is prebuilt and shipped in files/; nothing to fetch or compile.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/qemu-firmware-edk2/install
	# incus's edk2 driver matches firmware by NAME under /usr/share/OVMF: the GENERIC
	# (non-SecureBoot) pair is OVMF_CODE.fd + OVMF_VARS.fd, the SECUREBOOT pair is
	# OVMF_CODE.fd + OVMF_VARS.ms.fd. Ship all three there (plus /usr/share/qemu for
	# direct qemu use). OVMF_VARS.fd MUST be the empty store or SB stays enforced on
	# security.secureboot=false and unsigned images fail to boot.
	$(INSTALL_DIR) $(1)/usr/share/qemu $(1)/usr/share/OVMF
	$(INSTALL_DATA) ./files/OVMF_CODE.fd    $(1)/usr/share/qemu/OVMF_CODE.fd
	$(INSTALL_DATA) ./files/OVMF_VARS.fd    $(1)/usr/share/qemu/OVMF_VARS.fd
	$(INSTALL_DATA) ./files/OVMF_VARS.ms.fd $(1)/usr/share/qemu/OVMF_VARS.ms.fd
	ln -sf ../qemu/OVMF_CODE.fd    $(1)/usr/share/OVMF/OVMF_CODE.fd
	ln -sf ../qemu/OVMF_VARS.fd    $(1)/usr/share/OVMF/OVMF_VARS.fd
	ln -sf ../qemu/OVMF_VARS.ms.fd $(1)/usr/share/OVMF/OVMF_VARS.ms.fd
endef

$(eval $(call BuildPackage,qemu-firmware-edk2))
