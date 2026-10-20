# Design

How Nerves boots and updates on the FRAME156 without replacing the stock
bootloader.

The stock Rockchip boot chain stays untouched: the DDR init and miniloader
(idbloader), BL31 (`trust`), the vendor U-Boot (`uboot`), and the `resource`
partition. The firmware only rewrites the GPT, clears the bootloader message
at the start of `misc`, and writes the areas after the first 36 MiB. See
[fwup_include/fwup-common.conf](../fwup_include/fwup-common.conf) for the layout.

The vendor U-Boot has no persistent environment, and its distro boot doesn't
work on these units, so Nerves boots the way Android does. U-Boot's
`boot_android` loads an Android boot image (header v0) from the partition
named `boot`. After `reboot recovery` it loads the one named `recovery`,
once. Slot A's boot image is in p5 and slot B's in p6; the validated slot's
partition is named `boot`. Each boot image holds:

- the kernel, which carries our device tree (`ARM64_BUILTIN_DTB_OVERRIDE`,
  patch 0006), since U-Boot only copes with the stock one
- an empty initramfs, and a command line naming that slot's rootfs
- a Rockchip resource image with the *stock* device tree
  (`board/rk-kernel.dtb`). U-Boot builds its own drivers from it; without
  one, its PMIC driver doesn't probe and it drops into loader or recovery mode.

An upgrade writes the other slot's boot image and rootfs, then reboots with
`recovery` (fwup's `reboot_param`) to try it once. nerves_runtime's
`StartupGuard` validates it after the apps start, and validating rewrites
the GPT so the new slot's partition is named `boot`. If the new firmware
panics, hangs (the heart watchdog resets it), or loses power before that,
the next boot is the old firmware again; a hang before the watchdog starts
needs a power cycle. U-Boot doesn't touch the environment when it boots the
old slot, so `frame156-preinit` runs the `reconcile` task in `ops.fw` before
Erlang starts: when the running slot is the one named `boot`, it sets
`nerves_fw_active` and `nerves_fw_validated` back, and nerves_runtime sees
validated firmware from the start. On a slot that's on trial it changes
nothing. The U-Boot environment block at sector 73728 only
holds firmware metadata for nerves_runtime and fwup (`nerves_fw_boot_slot`
names the validated slot).

From Nerves, write `loader` to `/run/reboot-param` and reboot to get into
loader mode for `scripts/install-rockusb.sh` or a factory restore.

U-Boot also rewrites the first `console=` to `ttyFIQ0` and appends
`init=/init`, so the rootfs has `/init` linked to erlinit.

Recovery without tools: hold the power button while plugging in power, with
the USB-C cable to a computer, for loader mode. See
[recovery.md](recovery.md).
