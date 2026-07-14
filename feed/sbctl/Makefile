include $(TOPDIR)/rules.mk

# rollingWRT: sbctl, the Secure Boot key manager. One Go tool that generates the
# machine's own PK/KEK/db, enrolls them into firmware from Setup Mode, and signs
# EFI binaries (the UKI + sd-boot) with db. This is the lanzaboote model - no
# shim, no MOK - and it replaces both sbsigntool (sbsign) and efitools
# (cert-to-efi-sig-list / sign-efi-sig-list). Pure Go, cross-compiles clean.

PKG_NAME:=sbctl
PKG_VERSION:=0.18
PKG_RELEASE:=1

PKG_SOURCE:=sbctl-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/Foxboron/sbctl/archive/refs/tags/$(PKG_VERSION)
PKG_HASH:=7aa2af7b50d42abe39eb4875069ae5cd3fb8406d067d7a58b029c8270bacd14d

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=golang/host pcsc-lite
PKG_BUILD_PARALLEL:=1

GO_PKG:=github.com/foxboron/sbctl
GO_PKG_BUILD_PKG:=github.com/foxboron/sbctl/cmd/sbctl
GO_PKG_LDFLAGS_X:=github.com/foxboron/sbctl.Version=$(PKG_VERSION)
GO_PKG_INSTALL_BIN_PATH:=/usr/bin

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/sbctl
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Secure Boot key manager (create-keys / enroll-keys / sign)
  URL:=https://github.com/Foxboron/sbctl
  DEPENDS:=@TARGET_x86_64 $(GO_ARCH_DEPENDS) +libpcsclite
endef

define Package/sbctl/description
  Manages a machine's own Secure Boot keys (PK/KEK/db): generates them, enrolls
  them into firmware from Setup Mode, and signs EFI binaries (the UKI + sd-boot)
  with db. No shim, no MOK.
endef

$(eval $(call GoBinPackage,sbctl))
$(eval $(call BuildPackage,sbctl))
