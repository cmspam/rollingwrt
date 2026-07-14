include $(TOPDIR)/rules.mk

PKG_NAME:=incus
PKG_VERSION:=7.2.0
PKG_RELEASE:=2

PKG_SOURCE:=incus-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/lxc/incus/releases/download/v$(PKG_VERSION)
PKG_HASH:=f24644f968d0fbfbb6c6dbe57f4c6e30ae89b1b186e0f855b21ae640f6bcecda
PKG_BUILD_DIR:=$(BUILD_DIR)/incus-7.2

PKG_MAINTAINER:=cmspam
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/lxc/incus/v7
GO_PKG_BUILD_PKG:= \
	github.com/lxc/incus/v7/cmd/incusd \
	github.com/lxc/incus/v7/cmd/incus \
	github.com/lxc/incus/v7/cmd/incus-agent \
	github.com/lxc/incus/v7/cmd/incus-migrate
# libsqlite3: link the system sqlite (shared with cowsql) instead of go-sqlite3's bundled
# copy. sqlite_omit_load_extension: OpenWrt's libsqlite3 is built without the extension
# loader (SQLITE_OMIT_LOAD_EXTENSION), so without this tag go-sqlite3 references
# sqlite3_load_extension / sqlite3_enable_load_extension and the cgo link fails with
# undefined symbols. incus never loads sqlite extensions, so omitting them is safe.
GO_PKG_TAGS:=libsqlite3,sqlite_omit_load_extension
GO_PKG_INSTALL_BIN_PATH:=/usr/sbin

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

# incusd and incus link cowsql/sqlite (cgo), but incus-agent and incus-migrate run
# INSIDE guest VMs of arbitrary libc. The default cgo + PIE build links the agent to
# libsqlite3/libcowsql/libacl and needs the dynamic loader, none of which exist in a
# guest, so the agent crashes the instant it launches and incus never sees its
# STARTED signal (VMs then have no working agent: no exec, no reported state). Build
# the two guest-side binaries fully static and non-PIE (CGO_ENABLED=0, -buildmode
# exe) over the top of the normal build, mirroring how Alpine's incus package ships
# a static agent.
define Build/Compile
	$(call GoPackage/Build/Compile)
	$(GO_GENERAL_BUILD_CONFIG_VARS) \
	$(GO_PKG_BUILD_CONFIG_VARS) \
	$(GO_PKG_VARS) \
	CGO_ENABLED=0 \
	GO_BUILD_PKG="github.com/lxc/incus/v7/cmd/incus-agent github.com/lxc/incus/v7/cmd/incus-migrate" \
	$(SHELL) $(GO_INCLUDE_DIR)golang-build.sh build \
		-v -buildvcs=false -trimpath -buildmode exe -tags agent,netgo,static
endef

define Package/incus
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Incus container and virtual machine manager
  URL:=https://linuxcontainers.org/incus/
  # Build/link deps (staged to compile incus) plus the CONTAINER runtime deps that incusd
  # shells out to (dnsmasq-full/ip-full/rsync/attr/unsquashfs/prlimit/... - each breaks
  # instance create or start when missing). VM-only deps live in the incus-vm metapackage
  # below, so a container-only box does not drag in qemu/OVMF. Two deliberate omissions:
  #  - NO +lxc: incus links liblxc (the library, declared below), not the lxc CLI tools, so
  #    the CLI is not a dependency. liblxc pulls the lxc package on-device on its own.
  #  - NO +kmod-veth: a kmod is not buildable in a pkg job (it would compile against the SDK's
  #    stock kernel). kmod-veth ships in the kmods feed (built in the kernel job against our
  #    kernel); the assembler installs it with incus so container networking works. Same
  #    reasoning as zfs's kmod-fs-zfs. See planning/INSTALLER.md.
  DEPENDS:=$(GO_ARCH_DEPENDS) \
	+cowsql +cowsql-raft +libuv +libsqlite3 +liblxc +libopenssl +libudev-zero \
	+libacl +libcap \
	+dnsmasq-full +nftables-json +ip-full \
	+squashfs-tools-mksquashfs +squashfs-tools-unsquashfs +tar +xz +rsync +attr \
	+libcap-bin +shadow-utils +prlimit +incus-ui
endef

define Package/incus/description
  Incus is a modern, secure and powerful system container and virtual machine
  manager. This package provides the daemon (incusd) and CLI (incus), wired
  up for OpenWrt with the recommended sysctls, subuid/subgid ranges and a
  procd service.
endef

# Incus links cowsql/raft which use -Wl,-wrap,pthread_create and -Wl,-z,now.
GO_PKG_VARS+=CGO_LDFLAGS_ALLOW="(-Wl,-wrap,pthread_create)|(-Wl,-z,now)"

define Package/incus/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/incusd.init $(1)/etc/init.d/incus

	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_DATA) ./files/incus.sysctl $(1)/etc/sysctl.d/50-incus.conf

	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DATA) ./files/subuid $(1)/etc/subuid
	$(INSTALL_DATA) ./files/subgid $(1)/etc/subgid

	# LXC needs this bind-mount target dir to exist to prepare a container rootfs;
	# neither lxc nor liblxc ships it on OpenWrt, so container start fails with
	# "Failed to access to /usr/lib/lxc/rootfs" without it.
	$(INSTALL_DIR) $(1)/usr/lib/lxc/rootfs

	# incus manages its own bridges (incusbr0) with its own dnsmasq + nftables. Make
	# OpenWrt's stack cooperate on first boot: exclude incus bridges from the system
	# dnsmasq (bind-dynamic would otherwise grab their DHCP socket) and add them to the
	# lan firewall zone as a device (incusbr0 is not an OpenWrt-configured network).
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/incus.uci-defaults $(1)/etc/uci-defaults/90-incus
endef

# incus-vm (the VM-host metapackage) lives in its own feed Makefile (feed/incus-vm),
# NOT here: OpenWrt computes compile prerequisites per source directory, so its +qemu
# DEPENDS would otherwise become a hard build-prereq of incus/compile and drag the
# whole qemu/mesa/LLVM pole into the container-only (main) build track.

$(eval $(call GoBinPackage,incus))
$(eval $(call BuildPackage,incus))
