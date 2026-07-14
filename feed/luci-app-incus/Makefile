include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI link to the Incus web UI
LUCI_DEPENDS:=+luci-base +incus-ui-proxy
LUCI_PKGARCH:=all

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=Apache-2.0

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
