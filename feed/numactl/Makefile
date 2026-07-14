include $(TOPDIR)/rules.mk

PKG_NAME:=numactl
PKG_VERSION:=2.0.19
PKG_RELEASE:=1

PKG_SOURCE:=numactl-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/numactl/numactl/releases/download/v$(PKG_VERSION)
PKG_HASH:=f2672a0381cb59196e9c246bf8bcc43d5568bc457700a697f1a1df762b9af884

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=LGPL-2.1-only
PKG_LICENSE_FILES:=LICENSE.LGPL2.1
PKG_INSTALL:=1
PKG_FIXUP:=autoreconf

include $(INCLUDE_DIR)/package.mk

define Package/libnuma
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=NUMA policy library
  URL:=https://github.com/numactl/numactl
  DEPENDS:=@TARGET_x86_64 +libatomic
endef

define Package/libnuma/description
  Shared library for NUMA (Non-Uniform Memory Access) policy control. qemu links
  it for --enable-numa (NUMA-aware guests on multi-socket hosts).
endef

# headers + link libs into staging so qemu (--enable-numa) compiles against them
define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/include/numa*.h $(1)/usr/include/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libnuma.{a,so*} $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/numa.pc $(1)/usr/lib/pkgconfig/
endef

define Package/libnuma/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libnuma.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libnuma))
