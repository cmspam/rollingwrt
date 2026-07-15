include $(TOPDIR)/rules.mk

PKG_NAME:=usbredir
PKG_VERSION:=0.13.0
PKG_RELEASE:=1

PKG_SOURCE:=usbredir-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://www.spice-space.org/download/usbredir
PKG_HASH:=4ba6faa02c0ae6deeb4c53883d66ab54b3a5899bead42ce4ded9568b9a7dc46e

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=LGPL-2.1-or-later
PKG_LICENSE_FILES:=COPYING.LIB
PKG_INSTALL:=1
PKG_BUILD_DEPENDS:=libusb

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

# build only the libraries (parser + host); skip the standalone tools/tests
MESON_ARGS += -Dtools=disabled -Dtests=disabled -Dfuzzing=disabled

define Package/usbredir
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=USB traffic redirection libraries
  URL:=https://gitlab.freedesktop.org/spice/usbredir
  DEPENDS:=@TARGET_x86_64 +libusb-1.0
endef

define Package/usbredir/description
  libusbredirparser and libusbredirhost, used by qemu for --enable-usb-redir
  (redirecting USB devices to guests over SPICE).
endef

# headers + link libs + pkgconfig into staging so qemu (--enable-usb-redir) finds
# libusbredirparser-0.5 and libusbredirhost via pkg-config
define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/include/usbredir*.h $(1)/usr/include/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libusbredir*.{a,so*} $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/libusbredir*.pc $(1)/usr/lib/pkgconfig/
endef

define Package/usbredir/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libusbredir*.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,usbredir))
