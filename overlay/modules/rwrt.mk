# rollingWRT additions: in-tree kernel modules OpenWrt does not package.
# These are built by the kernel itself (package/kernel/linux), so they are plain
# KernelPackage defs with no build phase - the config overlay turns the symbols on.

define KernelPackage/vhost-vsock
  SUBMENU:=Virtualization
  TITLE:=Host kernel accelerator for virtio vsock
  DEPENDS:=@TARGET_x86_64 +kmod-vhost
  KCONFIG:=CONFIG_VHOST_VSOCK
  FILES:=$(LINUX_DIR)/drivers/vhost/vhost_vsock.ko
  AUTOLOAD:=$(call AutoProbe,vhost_vsock)
endef

define KernelPackage/vhost-vsock/description
  Host-side accelerator for virtio vsock, required by Incus to reach the
  incus-agent inside VM guests.
endef

$(eval $(call KernelPackage,vhost-vsock))


define KernelPackage/drm-gpuvm
  SUBMENU:=Video Support
  TITLE:=DRM GPU VA management (GPUVM)
  DEPENDS:=@TARGET_x86_64 +kmod-drm +kmod-drm-exec
  KCONFIG:=CONFIG_DRM_GPUVM
  FILES:=$(LINUX_DIR)/drivers/gpu/drm/drm_gpuvm.ko
  AUTOLOAD:=$(call AutoProbe,drm_gpuvm)
endef

$(eval $(call KernelPackage,drm-gpuvm))


define KernelPackage/drm-gpusvm
  SUBMENU:=Video Support
  TITLE:=DRM GPU shared virtual memory (GPUSVM)
  DEPENDS:=@TARGET_x86_64 +kmod-drm
  KCONFIG:=CONFIG_DRM_GPUSVM
  FILES:=$(LINUX_DIR)/drivers/gpu/drm/drm_gpusvm_helper.ko
  AUTOLOAD:=$(call AutoProbe,drm_gpusvm_helper)
endef

$(eval $(call KernelPackage,drm-gpusvm))


define KernelPackage/drm-xe
  SUBMENU:=Video Support
  TITLE:=Intel Xe DRM support
  DEPENDS:=@TARGET_x86_64 @DISPLAY_SUPPORT \
	+kmod-drm-ttm +kmod-drm-ttm-helper +kmod-drm-kms-helper \
	+kmod-drm-display-helper +kmod-drm-buddy +kmod-drm-exec \
	+kmod-drm-suballoc-helper +kmod-drm-gpuvm +kmod-drm-gpusvm \
	+kmod-drm-sched +kmod-i2c-algo-bit +kmod-backlight +kmod-acpi-video \
	+kmod-fs-configfs
  KCONFIG:=CONFIG_DRM_XE \
	CONFIG_DRM_XE_DISPLAY=y
  FILES:=$(LINUX_DIR)/drivers/gpu/drm/xe/xe.ko
  AUTOLOAD:=$(call AutoProbe,xe)
endef

define KernelPackage/drm-xe/description
  Intel Xe DRM driver for recent Intel GPUs (Lunar Lake and later, Arc/Battlemage).
endef

$(eval $(call KernelPackage,drm-xe))


define KernelPackage/tpm-crb
  SUBMENU:=Other modules
  TITLE:=TPM CRB interface
  DEPENDS:=@TARGET_x86_64 +kmod-tpm
  KCONFIG:=CONFIG_TCG_CRB
  FILES:=$(LINUX_DIR)/drivers/char/tpm/tpm_crb.ko
  AUTOLOAD:=$(call AutoProbe,tpm_crb)
endef

define KernelPackage/tpm-crb/description
  CRB interface driver, used by firmware TPMs (AMD fTPM, Intel PTT).
endef

$(eval $(call KernelPackage,tpm-crb))
