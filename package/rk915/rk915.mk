################################################################################
#
# rk915
#
################################################################################

RK915_VERSION = 87e2a4060af3f2508f05d1bff5724dbb381d0ae5
RK915_SITE = $(call github,rei512,rk915,$(RK915_VERSION))
RK915_LICENSE = GPL-2.0
RK915_LICENSE_FILES = LICENSE

RK915_MODULE_MAKE_OPTS = CONFIG_RK915=m

# The firmware is the same as the stock FRAME156 /vendor/etc/firmware files
define RK915_INSTALL_FIRMWARE
	$(INSTALL) -D -m 0644 $(@D)/firmware/rockchip/rk915_fw.bin \
		$(TARGET_DIR)/lib/firmware/rockchip/rk915_fw.bin
	$(INSTALL) -D -m 0644 $(@D)/firmware/rockchip/rk915_patch.bin \
		$(TARGET_DIR)/lib/firmware/rockchip/rk915_patch.bin
endef
RK915_POST_INSTALL_TARGET_HOOKS += RK915_INSTALL_FIRMWARE

$(eval $(kernel-module))
$(eval $(generic-package))
