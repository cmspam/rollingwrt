include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI link to the Incus web UI
LUCI_DEPENDS:=+luci-base +incus-ui-proxy
LUCI_PKGARCH:=all

# Pin the version. Without PKG_VERSION, luci.mk derives it from git as
# <yday>.<secs>~<hash>, which (a) changes every commit so old apks pile up on the feed
# and (b) contains a '~' that GitHub Releases rewrites to '.' in the asset filename,
# leaving the apk undownloadable (apk requests the ~ URL, gets a 404). A menu-link app
# needs no git version; bump PKG_RELEASE by hand when the app actually changes.
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=Apache-2.0

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
