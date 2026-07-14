include $(TOPDIR)/rules.mk

PKG_NAME:=cowsql
PKG_VERSION:=1.15.9
PKG_RELEASE:=1

PKG_SOURCE:=cowsql-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/cowsql/cowsql/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=257aee775f68fd145bfae012dc394fdf62c2f97f0360b0bcf6bd1f66bc58ca04
PKG_BUILD_DIR:=$(BUILD_DIR)/cowsql-$(PKG_VERSION)

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=LGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/cowsql
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Embeddable, replicated SQL database engine
  URL:=https://github.com/cowsql/cowsql
  DEPENDS:=+libuv +libsqlite3 +cowsql-raft
endef

define Package/cowsql/description
  cowsql is a C library implementing an embeddable, replicated SQL database
  engine built on SQLite and the Raft consensus protocol. Used by Incus.
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include $(1)/usr/lib $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/include/cowsql.h $(1)/usr/include/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libcowsql.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/cowsql.pc $(1)/usr/lib/pkgconfig/ 2>/dev/null || true
endef

define Package/cowsql/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libcowsql.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,cowsql))
