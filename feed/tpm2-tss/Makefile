include $(TOPDIR)/rules.mk

# rollingWRT: the TPM2 Software Stack (libtss2). Foundational dependency of
# tpm2-tools, which every rollingWRT TPM operation (enroll, unseal, sign-policy,
# initramfs unlock) shells out to. Builds clean on musl (Alpine ships it, no
# patches). FAPI is disabled: our commands are all ESYS/SYS, so we avoid pulling
# curl + json-c. Default TCTI is the kernel resource manager (/dev/tpmrm0).

PKG_NAME:=tpm2-tss
PKG_VERSION:=4.1.2
PKG_RELEASE:=1

PKG_SOURCE:=tpm2-tss-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/tpm2-software/tpm2-tss/releases/download/$(PKG_VERSION)
PKG_HASH:=6ad3ef0993cf3bc953710abed847ff727ab427b5577e812e3ad3197bbcec069e

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=BSD-2-Clause
PKG_LICENSE_FILES:=LICENSE
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/tpm2-tss
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=TPM2 Software Stack (libtss2)
  URL:=https://github.com/tpm2-software/tpm2-tss
  DEPENDS:=@TARGET_x86_64 +libopenssl +libuuid +libjson-c +libusb-1.0
endef

define Package/tpm2-tss/description
  ESYS/SYS/MU/TCTI libraries (libtss2-*) that tpm2-tools links against. Default
  TCTI is the in-kernel resource manager device (/dev/tpmrm0).
endef

CONFIGURE_ARGS += \
	--with-tctidefaultmodule=device \
	--with-tctidefaultconfig=/dev/tpmrm0 \
	--with-crypto=ossl \
	--disable-fapi \
	--disable-unit \
	--disable-integration \
	--disable-doxygen-doc \
	--disable-tcti-swtpm \
	--disable-tcti-mssim

# headers + libs + pkgconfig into staging so tpm2-tools compiles against them
define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include $(1)/usr/lib $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/include/tss2 $(1)/usr/include/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libtss2*.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/tss2-*.pc $(1)/usr/lib/pkgconfig/
endef

define Package/tpm2-tss/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libtss2*.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,tpm2-tss))
