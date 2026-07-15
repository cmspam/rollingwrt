include $(TOPDIR)/rules.mk

# rollingWRT: systemd's EFI components (sd-stub + sd-boot) built from source.
#
# The UKI must be an sd-stub UKI: sd-stub measures the UKI's PE sections into
# PCR 11 at boot (rollingwrt-pcr11-predict reproduces that exactly). sd-boot is
# the loader that enrolls our own Secure Boot keys from firmware Setup Mode. Both
# are FREESTANDING EFI PE binaries for x86_64 - they do NOT link the target musl
# libc - so they are built with the host toolchain (host is x86_64 too) and
# shipped to the target as data, like firmware blobs.
#
# Proven recipe: systemd v261 + meson -Defi=true -Dbootloader=enabled, with host
# meson/ninja + python jinja2 + pyelftools (in the build Containerfile). Targets:
#   src/boot/linuxx64.efi.stub   src/boot/systemd-bootx64.efi

PKG_NAME:=systemd-boot
PKG_VERSION:=261
PKG_RELEASE:=1

# systemd tags are v-prefixed (v261). GitHub serves the tag archive under any
# trailing filename, so .../archive/v261/systemd-261.tar.gz downloads v261 but
# keeps our stable local name (and extracts to systemd-261/, matching PKG_BUILD_DIR).
PKG_SOURCE:=systemd-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/systemd/systemd/archive/v$(PKG_VERSION)
PKG_HASH:=f1c2e6a0d19ea5cae946386eb288432de12f3c6b7730cdb0d2a06f8ab8e3f8dc
PKG_BUILD_DIR:=$(BUILD_DIR)/systemd-$(PKG_VERSION)

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=LGPL-2.1-or-later

include $(INCLUDE_DIR)/package.mk

EFI_ARCH:=x64

define Package/systemd-boot
  SECTION:=boot
  CATEGORY:=Base system
  TITLE:=systemd EFI stub + boot loader (sd-stub, sd-boot)
  URL:=https://systemd.io
  DEPENDS:=@TARGET_x86_64
endef

define Package/systemd-boot/description
  linux$(EFI_ARCH).efi.stub (the UKI stub that measures sections into PCR 11) and
  systemd-boot$(EFI_ARCH).efi (the loader that auto-enrolls own Secure Boot keys
  from firmware Setup Mode). Installed under /usr/lib/systemd/boot/efi so
  rollingwrt-uki can assemble UKIs with objcopy.
endef

# Build the two EFI binaries with the host meson/ninja (freestanding, arch-native,
# not target-libc linked). meson + ninja + python3 (jinja2, pyelftools) come from
# the build container / CI image. Done in one step to avoid OpenWrt's split
# configure/compile stamp wiring (these are host tools, not the target toolchain).
# Use the SYSTEM PATH (not OpenWrt's staging hostpkg) so meson finds the system
# python3 with jinja2/pyelftools/distutils, plus the host gcc/ninja. The EFI
# binaries are freestanding, so the target musl toolchain is not involved.
define Build/Compile
	rm -rf $(PKG_BUILD_DIR)/build-efi
	cd $(PKG_BUILD_DIR) && PATH=/usr/bin:/bin meson setup build-efi . \
		-Defi=true -Dbootloader=enabled -Dukify=disabled -Dman=disabled -Dtests=false
	PATH=/usr/bin:/bin ninja -C $(PKG_BUILD_DIR)/build-efi \
		src/boot/linux$(EFI_ARCH).efi.stub src/boot/systemd-boot$(EFI_ARCH).efi
endef

define Package/systemd-boot/install
	$(INSTALL_DIR) $(1)/usr/lib/systemd/boot/efi
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build-efi/src/boot/linux$(EFI_ARCH).efi.stub \
		$(1)/usr/lib/systemd/boot/efi/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build-efi/src/boot/systemd-boot$(EFI_ARCH).efi \
		$(1)/usr/lib/systemd/boot/efi/
endef

$(eval $(call BuildPackage,systemd-boot))
