include $(TOPDIR)/rules.mk

PKG_NAME:=incus-vm
PKG_VERSION:=7.2.0
PKG_RELEASE:=1

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

# Pure metapackage: the payload is the DEPENDS. It lives in its own source directory
# (not incus/Makefile) so its +qemu DEPENDS stays out of incus/compile's prerequisite
# graph. That keeps the container-only build track (main) free of the qemu/mesa/LLVM
# pole; incus-vm is built and shipped by the gpu track, alongside qemu.
define Package/incus-vm
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Incus virtual-machine support (qemu + OVMF + KVM/vhost kmods)
  URL:=https://linuxcontainers.org/incus/
  DEPENDS:=+incus +qemu-x86_64-softmmu +qemu-img +qemu-firmware-edk2 \
	+kmod-kvm-amd +kmod-kvm-intel +kmod-vhost-net +kmod-vhost-vsock +kmod-tun
endef

define Package/incus-vm/description
  Metapackage that turns an incus install into a VM host: qemu, the OVMF/EDK2 UEFI
  firmware, and the host virtualization kernel modules (KVM for both AMD and Intel,
  vhost-net, vhost-vsock, tun). Install alongside incus to run virtual machines;
  plain incus already runs system containers without any of this.
endef

# No source to build.
define Build/Compile
endef

define Package/incus-vm/install
	# Ship a marker so the package is not empty; the real payload is the DEPENDS.
	$(INSTALL_DIR) $(1)/usr/lib/incus
	echo "vm" > $(1)/usr/lib/incus/vm-support
endef

$(eval $(call BuildPackage,incus-vm))
