include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=zfs
PKG_VERSION:=2.4.3
PKG_RELEASE:=1

PKG_SOURCE:=zfs-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/openzfs/zfs/releases/download/zfs-$(PKG_VERSION)
PKG_HASH:=1f08f2d154f5189b5f1382848a32667b3d34066145b474c49cd3d41a5fba59a7

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=CDDL-1.0
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_PARALLEL:=1
PKG_INSTALL:=1
PKG_BUILD_FLAGS:=no-mips16

PKG_BUILD_DEPENDS:=libtirpc

include $(INCLUDE_DIR)/package.mk

define KernelPackage/fs-zfs
  SUBMENU:=Filesystems
  TITLE:=OpenZFS filesystem and volume manager
  URL:=https://openzfs.org
  DEPENDS:=@TARGET_x86_64 +zlib +libuuid +libblkid +libtirpc
  # OpenZFS 2.4.x ships two modules; the former sub-modules (avl, nvpair, icp,
  # lua, zstd, ...) are now linked into zfs.ko.
  FILES:= \
	$(PKG_BUILD_DIR)/module/spl.ko \
	$(PKG_BUILD_DIR)/module/zfs.ko
  AUTOLOAD:=$(call AutoLoad,30,spl zfs)
endef

define KernelPackage/fs-zfs/description
  OpenZFS kernel modules. The Incus ZFS storage backend uses these for instant
  CoW snapshots/clones of containers and VMs.
endef

# Split the one shared OpenZFS build across two CI jobs. OpenZFS compiles its kernel
# modules and its userspace from ONE source tree; --with-config selects which half.
# kmod-fs-zfs is an out-of-tree module, so it MUST be built against OUR kernel: the
# kernel job sets ZFS_WITH_CONFIG=kernel (modules only, no userspace deps), and the
# userland job sets ZFS_WITH_CONFIG=user (zpool/zfs only, no module). Default `all`
# still builds everything for a one-shot local build.
ZFS_WITH_CONFIG ?= all
CONFIGURE_ARGS += \
	--with-linux=$(LINUX_DIR) \
	--with-linux-obj=$(LINUX_DIR) \
	--with-config=$(ZFS_WITH_CONFIG) \
	--enable-linux-builtin=no \
	--with-tirpc \
	--disable-sysvinit \
	--disable-systemd \
	--disable-pyzfs \
	--without-python \
	--disable-pam \
	--with-mounthelperdir=/sbin \
	--with-udevdir=/lib/udev \
	--with-systemdunitdir=/dev/null \
	--with-systemdpresetdir=/dev/null

CONFIGURE_VARS += \
	KERNEL_CC="$(KERNEL_CC)" \
	KERNEL_LD="$(TARGET_CROSS)ld" \
	KERNEL_LLVM="" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	ARCH="$(LINUX_KARCH)"

# musl: zfs trips tree-vectorize
TARGET_CFLAGS += -fno-tree-vectorize

# Build both modules and userspace (--with-config=all). The kernel module kbuild
# needs the cross env; KCFLAGS disables a GCC-14 false-positive infinite-recursion
# error in ZFS's bundled lua (ldo.c).
MAKE_FLAGS += \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	ARCH="$(LINUX_KARCH)" \
	KCFLAGS="-Wno-error=infinite-recursion -Wno-infinite-recursion"

define Package/zfs
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=OpenZFS userspace utilities (zpool, zfs)
  URL:=https://openzfs.org
  # NO +kmod-fs-zfs here on purpose. OpenWrt builds a package's DEPENDS as compile
  # prerequisites, so declaring the module would drag the kmod build into the userland
  # job - against the SDK's stock kernel - which is exactly what must not happen (the
  # module is built only in the kernel job, against our kernel). The device gets both:
  # the assembler installs zfs + kmod-fs-zfs together (zfs is core to the NAS role), and
  # the kmod comes from the kmods feed. See planning/INSTALLER.md.
  DEPENDS:=+zlib +libuuid +libblkid +libtirpc +libopenssl +libudev-zero
endef

define Package/zfs/description
  OpenZFS userspace tools: zpool, zfs and supporting libraries.
endef

define Package/zfs/install
	$(INSTALL_DIR) $(1)/sbin $(1)/usr/sbin $(1)/usr/lib $(1)/usr/lib/zfs
	# core tools (OpenZFS installs zpool/zfs to /usr/sbin; mount.zfs to /sbin)
	$(CP) $(PKG_INSTALL_DIR)/usr/sbin/zpool $(1)/usr/sbin/
	$(CP) $(PKG_INSTALL_DIR)/usr/sbin/zfs $(1)/usr/sbin/
	$(CP) $(PKG_INSTALL_DIR)/usr/sbin/zdb $(1)/usr/sbin/
	$(CP) $(PKG_INSTALL_DIR)/usr/sbin/zstream $(1)/usr/sbin/
	$(CP) $(PKG_INSTALL_DIR)/sbin/mount.zfs $(1)/sbin/ 2>/dev/null || true
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/lib{zfs,zfs_core,zpool,nvpair,uutil,zfsbootenv}.so.* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/zfs $(1)/usr/lib/ 2>/dev/null || true
endef

$(eval $(call KernelPackage,fs-zfs))
$(eval $(call BuildPackage,zfs))
