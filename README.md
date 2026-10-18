# Pastigio FRAME156 Nerves system

A [Nerves](https://nerves-project.org) system for the Pastigio FRAME156, a
15.6" Frameo photo frame built on the Rockchip RK3326.

**Status: bring-up.** Nerves boots on unit 1: IEx over ssh on the
USB-C network, display working, and A/B upgrades over the network (`mix
upload`) that fall back on their own if the new firmware fails.

| Feature              | Status |
|----------------------|--------|
| CPU                  | 4x Cortex-A35, aarch64; cpufreq works |
| Memory               | 1 GB DRAM |
| Storage              | 29.8 GB eMMC; works |
| Linux kernel         | 7.1.2 (mainline, ROCKNIX RK3326 config); boots |
| IEx terminal         | USB-C serial gadget (`ttyGS0`) |
| USB-C                | Device only: CDC ECM network + ACM serial; works |
| USB-A                | Host; VBUS on |
| Display              | 1920x1080 eDP through a Lontium LT8911EXB DSI bridge; works (our bridge driver, patch 0005, plus a panel-edp entry) |
| Wi-Fi                | RK915 SDIO, 2.4 GHz only; scans (community driver, package/rk915) |
| Bluetooth            | None on the board (the RK915 is Wi-Fi only) |
| Audio                | RK809 codec + speaker amp; plays (`aplay`, `speaker-test`) |
| Touchscreen          | Silead GSL3676; driver loads, touches not decoded yet |
| Backlight            | PWM, `/sys/class/backlight/backlight` (0-255); works |
| Power button         | RK809 power key input; works |
| RTC                  | HYM8563; probes |
| Watchdog             | dw_wdt; works |
| Bootloader           | Stock Rockchip vendor U-Boot 2017.09, kept as-is |
| Reboot modes         | `loader` and `recovery` work (PSCI restart, patch 0007) |

Units differ: unit 1 has a 1920x1080 panel, and unit 2 (newer
firmware) has a 1366x768 panel with different bridge settings.

See [docs/hardware.md](docs/hardware.md) for everything learned from the stock
firmware.

## Design

The stock Rockchip boot chain stays untouched: the DDR init and miniloader
(idbloader), BL31 (`trust`), the vendor U-Boot (`uboot`), and the `resource`
partition. The firmware only rewrites the GPT, clears the bootloader message
at the start of `misc`, and writes the areas after the first 36 MiB. See
[fwup_include/fwup-common.conf](fwup_include/fwup-common.conf) for the layout.

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
needs a power cycle. The U-Boot environment block at sector 73728 only
holds firmware metadata for nerves_runtime and fwup (`nerves_fw_boot_slot`
names the validated slot).

From Nerves, write `loader` to `/run/reboot-param` and reboot to get into
loader mode for `scripts/install-rockusb.sh` or a factory restore.

U-Boot also rewrites the first `console=` to `ttyFIQ0` and appends
`init=/init`, so the rootfs has `/init` linked to erlinit.

Recovery without tools: hold the power button while plugging in power, with
the USB-C cable to a computer, for loader mode. See
[docs/recovery.md](docs/recovery.md).

## Getting into the frame

The USB-C port is the OTG port. Use a USB-A-to-C cable; C-to-C doesn't
enumerate. Plug in the frame's own power supply too: laptop USB power
alone browns the board out once Nerves starts, which looks like a boot
loop.

From stock Android (enable Frameo **Settings → About → Beta → ADB Access**):

| Command                               | Result |
|---------------------------------------|--------|
| `adb reboot loader`                   | rockusb loader mode (`2207:330d`), for `rkdeveloptool` |
| `adb shell su -c 'reboot ums'`        | eMMC as a USB mass-storage disk |
| `adb reboot fastboot`                 | U-Boot fastboot |
| `adb reboot recovery`                 | Boots whatever is in the `recovery` partition |

`rkdeveloptool` needs a udev rule for Rockchip devices, for example
`/etc/udev/rules.d/60-rockchip.rules`:

```
SUBSYSTEM=="usb", ATTRS{idVendor}=="2207", MODE="0660", TAG+="uaccess"
```

Note that the installed `rkdeveloptool`'s `rl` (read LBA) takes its length in
bytes, not sectors.

## Back up first

`scripts/backup.sh` copies every eMMC partition except userdata over ADB,
verifying each one against a hash computed on the frame. It also saves the
live device tree, kernel config and logs that the port is based on. Run it
before writing anything.

## Bring-up: test kernels via the recovery partition

`scripts/build-test-kernel.sh` builds the kernel and a small busybox
initramfs (about five minutes), and packs them like the stock recovery image.
Android keeps working, and the stock recovery image is in the backup.

```sh
STOCK_RESOURCE=path/to/stock/resource.img scripts/build-test-kernel.sh
adb push .build/test/recovery.img /data/local/tmp/
adb shell su -c 'dd if=/data/local/tmp/recovery.img of=/dev/block/mmcblk2p7 bs=1M'
adb reboot recovery
```

The test kernel's initramfs serves a shell over the USB cable:

- Network: the frame is `172.31.207.1` and gives the host an address over
  DHCP. `socat - TCP:172.31.207.1:2323`, or `telnet 172.31.207.1`.
- Serial: `/dev/ttyACM0`.

A cold power cycle returns to Android. The kernel log is kept in ramoops at
the same address and layout as stock Android's, so after a failed test boot
Android shows it in `/sys/fs/pstore`.

## Building

```sh
mix deps.get
# then use this system as a dependency of a Nerves project
```

Host requirements are the usual Nerves ones (`fwup`, `squashfs-tools`, `bc`,
and so on).

## Installing

Put the frame in loader mode (`adb reboot loader` from Android, or the
power-button escape), then:

```sh
scripts/install-rockusb.sh example/_build/frame156_dev/nerves/images/frame_example.fw
rkdeveloptool rd
```

The example app in `example/` authorizes its own SSH key (`example/.ssh/`,
git-ignored). The frame appears on a USB network (VintageNetDirect); log in
with `ssh -i example/.ssh/frame156_ed25519 nerves.local`.

To go back to Android: `scripts/factory-restore.sh backups/<serial>` from
loader mode.
