include $(TOPDIR)/rules.mk

# rollingWRT: the tpm2_* command-line tools. Every rollingWRT TPM operation shells
# out to these: rollingwrt-tpm-enroll (createprimary/create/load/evictcontrol/
# policyauthorize), rollingwrt-tpm-unseal (startauthsession/policypcr/unseal),
# rollingwrt-tpm-sign-policy (policypcr trial), and the initramfs unlock. Builds
# clean on musl (Alpine, no patches). FAPI tools disabled (we use ESYS only).

PKG_NAME:=tpm2-tools
PKG_VERSION:=5.7
PKG_RELEASE:=1

PKG_SOURCE:=tpm2-tools-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/tpm2-software/tpm2-tools/releases/download/$(PKG_VERSION)
PKG_HASH:=3810d36b5079256f4f2f7ce552e22213d43b1031c131538df8a2dbc3c570983a

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/tpm2-tools
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=TPM2 command-line tools (tpm2_*)
  URL:=https://github.com/tpm2-software/tpm2-tools
  DEPENDS:=@TARGET_x86_64 +tpm2-tss +libopenssl +libcurl +libuuid +efivar
endef

define Package/tpm2-tools/description
  The tpm2_* utilities used for TPM2 LUKS auto-unlock: sealing a key under a
  signed PCR-11 PolicyAuthorize policy and unsealing it at boot.
endef

CONFIGURE_ARGS += --disable-fapi --disable-unit

define Package/tpm2-tools/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(CP) $(PKG_INSTALL_DIR)/usr/bin/tpm2 $(1)/usr/bin/
	# tpm2-tools installs tpm2_<cmd> symlinks to the single tpm2 dispatcher
	$(CP) $(PKG_INSTALL_DIR)/usr/bin/tpm2_* $(1)/usr/bin/ 2>/dev/null || true
endef

$(eval $(call BuildPackage,tpm2-tools))
