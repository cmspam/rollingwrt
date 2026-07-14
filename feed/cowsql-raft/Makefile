include $(TOPDIR)/rules.mk

PKG_NAME:=cowsql-raft
PKG_VERSION:=0.22.1
PKG_RELEASE:=1

PKG_SOURCE:=raft-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/cowsql/raft/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=385f91a0b542ebe8b81c8f8500310dcd575fd028ea0cd2ede8807fa920dcf604
PKG_BUILD_DIR:=$(BUILD_DIR)/raft-$(PKG_VERSION)

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=LGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/cowsql-raft
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Raft consensus protocol library (cowsql fork)
  URL:=https://github.com/cowsql/raft
  DEPENDS:=+libuv
endef

define Package/cowsql-raft/description
  Asynchronous, fully replicated FSM library based on the Raft consensus
  protocol. cowsql fork used by cowsql and Incus.
endef

CONFIGURE_ARGS += \
	--without-lz4 \
	--enable-example=no

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include $(1)/usr/lib $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/include/raft.h $(1)/usr/include/
	$(CP) -r $(PKG_INSTALL_DIR)/usr/include/raft $(1)/usr/include/ 2>/dev/null || true
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libraft.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/raft.pc $(1)/usr/lib/pkgconfig/ 2>/dev/null || true
endef

define Package/cowsql-raft/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libraft.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,cowsql-raft))
