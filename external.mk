# Include system-specific packages
include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/package/*/*.mk))

# The kernel links our device tree in (CONFIG_ARM64_BUILTIN_DTB_OVERRIDE),
# so the vendor U-Boot can keep using the stock one from the resource
# partition. Build the DTB before the kernel so the .incbin finds it.
define FRAME156_LINUX_BUILD_DTB_FIRST
	cp -f $(NERVES_DEFCONFIG_DIR)/dts/rk3326-pastigio-frame156.dts $(LINUX_ARCH_PATH)/boot/dts/
	$(LINUX_MAKE_ENV) $(BR2_MAKE) $(LINUX_MAKE_FLAGS) -C $(@D) rk3326-pastigio-frame156.dtb
	rm -f $(@D)/arch/arm64/kernel/builtin_dtb.o
endef
LINUX_PRE_BUILD_HOOKS += FRAME156_LINUX_BUILD_DTB_FIRST
