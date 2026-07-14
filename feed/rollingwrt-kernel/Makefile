include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

# rollingWRT: package the bootable kernel image (bzImage) as an owned apk file.
#
# Stock OpenWrt's `kernel` apk is metadata only (vermagic + builtin module list);
# the real vmlinuz is baked into the image and never updated by apk. This inverts
# that: /boot/vmlinuz-<version> is owned by this package, versioned by the kernel
# vermagic, and pinned to the exact `kernel` marker. So `apk upgrade` moves the
# kernel binary in lockstep with its modules, and rollingwrt-boot's /boot +
# /lib/modules trigger rebuilds and re-signs the UKI in the same transaction.

PKG_NAME:=rollingwrt-kernel
PKG_RELEASE:=1
PKG_MAINTAINER:=cmspam
PKG_LICENSE:=GPL-2.0-only
PKG_FLAGS:=nonshared

include $(INCLUDE_DIR)/package.mk

define Package/rollingwrt-kernel
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=rollingWRT bootable kernel image (UKI payload)
  # VERSION carries the kernel vermagic as a cksum decimal after a . (not the hex
  # after a ~), so the apk filename survives GitHub Releases, which rewrites ~ to .
  # A kernel change bumps this apk and `apk upgrade` moves the vmlinuz in lockstep
  # with its kmods. EXTRA_DEPENDS pins the exact `kernel` marker at the apk level
  # (not Kconfig, so selectability is unaffected). This package only ever has a newer
  # version in our feed, so its exact pin holds the whole kernel set (marker + vmlinuz
  # + kmods) on our version until our feed ships the next one, even when a newer
  # OpenWrt kernel would otherwise out-rank ours during a version-bump lag window.
  VERSION:=$(subst -rc,_rc,$(LINUX_VERSION)).$(LINUX_VERMAGIC_DEC)-r$(PKG_RELEASE)
  EXTRA_DEPENDS:=kernel (=$(subst -rc,_rc,$(LINUX_VERSION)).$(LINUX_VERMAGIC_DEC)-r$(LINUX_RELEASE))
  DEPENDS:=+rollingwrt-boot
endef

define Package/rollingwrt-kernel/description
  Ships the compressed kernel image as /boot/vmlinuz-$(LINUX_VERSION), owned by an
  apk so kernel updates flow through `apk upgrade`. Installing it triggers a UKI
  rebuild (rollingwrt-boot). The filename uses the bare kernel version to match
  the /lib/modules directory that rollingwrt-uki reads as KVER.
endef

# no upstream source; this package only repackages the kernel build artifact.
# still create PKG_BUILD_DIR so the .built stamp can be written.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef
Build/Configure:=:
Build/Compile:=:

define Package/rollingwrt-kernel/install
	$(INSTALL_DIR) $(1)/boot
	$(CP) $(LINUX_DIR)/arch/$(LINUX_KARCH)/boot/bzImage \
		$(1)/boot/vmlinuz-$(LINUX_VERSION)
endef

$(eval $(call BuildPackage,rollingwrt-kernel))
