include $(TOPDIR)/rules.mk

PKG_NAME:=incus-ui
PKG_VERSION:=7.2
# Build stamp of the upstream incus-ui-canonical .deb. The update bumper resolves
# the newest stamp (and hash) from the Zabbly Packages index.
PKG_DEB_STAMP:=202607101628
PKG_RELEASE:=1

PKG_SOURCE:=incus-ui-canonical_$(PKG_VERSION)-debian13-$(PKG_DEB_STAMP)_amd64.deb
PKG_SOURCE_URL:=https://pkgs.zabbly.com/incus/stable/pool/main/i/incus
PKG_HASH:=2abd49faa5bee911c4d5da880f6d3966f12a6c7215e5a5355fab4cf4e3ebb989

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=AGPL-3.0-only

include $(INCLUDE_DIR)/package.mk

# The UI is a prebuilt, architecture-independent JS/HTML bundle (a fork of
# canonical/lxd-ui) shipped inside the Zabbly incus-ui-canonical .deb. We unpack
# the .deb directly instead of rebuilding from source, which would pull in a full
# Node toolchain. The default unpack step only handles tarballs, so Build/Prepare
# extracts the .deb's data archive by hand.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	ar p $(DL_DIR)/$(PKG_SOURCE) data.tar.xz | $(TAR) -xJ -C $(PKG_BUILD_DIR) ./opt/incus/ui
endef

define Build/Compile
endef

define Package/incus-ui
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Incus web UI
  URL:=https://github.com/zabbly/incus-ui-canonical
  # No +incus dependency: incus already DEPENDS +incus-ui (it bundles and serves these
  # static files), and adding the reverse makes a recursive dependency that aborts the
  # kconfig/metadata step. The web UI ships with incus; it never installs on its own.
  PKGARCH:=all
endef

define Package/incus-ui/description
  Prebuilt static web UI for Incus (a fork of canonical/lxd-ui). incusd serves it
  when the INCUS_UI environment variable points at a directory containing it; the
  incus package's service sets INCUS_UI=/usr/share/incus/ui.
endef

define Package/incus-ui/install
	$(INSTALL_DIR) $(1)/usr/share/incus/ui
	$(CP) $(PKG_BUILD_DIR)/opt/incus/ui/. $(1)/usr/share/incus/ui/
endef

$(eval $(call BuildPackage,incus-ui))
