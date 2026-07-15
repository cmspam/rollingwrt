include $(TOPDIR)/rules.mk

PKG_NAME:=virglrenderer
PKG_VERSION:=1.3.0
PKG_RELEASE:=1

PKG_SOURCE:=virglrenderer-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://gitlab.freedesktop.org/virgl/virglrenderer/-/archive/$(PKG_VERSION)
PKG_HASH:=065bc56e89e6f631f96101cd62eba0748e48eb888b434edc86e89d05395e76f3

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=COPYING
PKG_BUILD_PARALLEL:=1

PKG_BUILD_DEPENDS:=libdrm libepoxy

# virglrenderer bundles mesa's gallium codegen, which needs yaml/mako in the
# host python. Use the same idiomatic recipe as OpenWrt's mesa package:
# MESON_USE_STAGING_PYTHON pins one consistent host python, and the modules are
# installed into it from host-pip-requirements.txt.
PYTHON3_PKG_BUILD:=0
MESON_USE_STAGING_PYTHON:=1
HOST_PYTHON3_PACKAGE_BUILD_DEPENDS:=./host-pip-requirements.txt

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/host-build.mk
include $(TOPDIR)/feeds/packages/lang/python/python3-package.mk
include $(INCLUDE_DIR)/meson.mk

define Package/virglrenderer
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Virgl/DRM-native-context renderer (AMDGPU + Intel i915/Xe)
  URL:=https://gitlab.freedesktop.org/virgl/virglrenderer
  DEPENDS:=+libdrm +libdrm-amdgpu +libepoxy
endef

define Package/virglrenderer/description
  virglrenderer with DRM native context backends enabled (amdgpu, i915 and
  the out-of-tree Intel Xe driver), for GPU passthrough to qemu/Incus VMs.
endef

MESON_ARGS += \
	-Ddrm-renderers=amdgpu-experimental,i915-experimental,xe-experimental \
	-Dvenus=false \
	-Dtests=false \
	-Dfuzzer=false

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include $(1)/usr/lib $(1)/usr/lib/pkgconfig
	$(CP) -r $(PKG_INSTALL_DIR)/usr/include/virgl* $(1)/usr/include/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libvirglrenderer.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/virglrenderer.pc $(1)/usr/lib/pkgconfig/
endef

define Package/virglrenderer/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libvirglrenderer.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,virglrenderer))
