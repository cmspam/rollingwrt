include $(TOPDIR)/rules.mk

PKG_NAME:=incus-ui-proxy
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_MAINTAINER:=cmspam
PKG_LICENSE:=Apache-2.0

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1

# Module path; must match the module line in src/go.mod. The source is local
# (src/), so there is no PKG_SOURCE to fetch and Build/Prepare stages it by hand.
GO_PKG:=github.com/cmspam/rollingwrt/incus-ui-proxy
GO_PKG_INSTALL_BIN_PATH:=/usr/sbin

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/incus-ui-proxy
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=LuCI-authenticated reverse proxy for the Incus web UI
  URL:=https://github.com/cmspam/rollingwrt
  # A plain host-side daemon: dynamic musl linking is fine here (unlike the guest
  # incus-agent). incus-ui provides the static UI incusd serves over the socket.
  DEPENDS:=$(GO_ARCH_DEPENDS) +incus +incus-ui
endef

define Package/incus-ui-proxy/description
  A small reverse proxy that exposes the Incus web UI and REST API to a browser
  over an HTTPS port, using Incus's local unix socket (a full-trust admin channel,
  no client certificate) as the backend. Every request is gated on the caller's
  LuCI session via ubus, so a logged-in LuCI user reaches the UI without enrolling
  a certificate. Websocket upgrades (the event stream and instance consoles) are
  forwarded transparently. Pair with luci-app-incus, which adds the menu link.
endef

# The source is a stdlib-only Go module in src/; stage it at the build root where
# golang-build.sh expects the module (it symlinks it into the build GOPATH).
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Package/incus-ui-proxy/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/incus-ui-proxy.init $(1)/etc/init.d/incus-ui-proxy

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/incus-ui-proxy.config $(1)/etc/config/incus-ui-proxy
endef

$(eval $(call GoBinPackage,incus-ui-proxy))
$(eval $(call BuildPackage,incus-ui-proxy))
