# Pastigio FRAME156 Nerves system

A [Nerves](https://nerves-project.org) system for the Pastigio FRAME156, a
15.6" Frameo photo frame built on the Rockchip RK3326.

**Status: bring-up.** The mainline kernel boots on hardware (as a one-shot
test image from the recovery partition). The Nerves system itself hasn't
been installed yet.

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
| Wi-Fi                | RK915 SDIO; no driver yet (use a USB dongle) |
| RTC                  | HYM8563; probes |
| Watchdog             | dw_wdt; works |
| Bootloader           | Stock Rockchip vendor U-Boot 2017.09, kept as-is |

Units differ: unit 1 has a 1920x1080 panel, and unit 2 (newer
firmware) has a 1366x768 panel with different bridge settings.

See [docs/hardware.md](docs/hardware.md) for everything learned from the stock
firmware.

## Design

The stock Rockchip boot chain stays untouched: the DDR init and miniloader
(idbloader), BL31 (`trust`), the vendor U-Boot (`uboot`), and the `resource`
partition U-Boot reads its boot logo from. The firmware only rewrites the GPT
and the areas after the first 36 MiB. See
[fwup_include/fwup-common.conf](fwup_include/fwup-common.conf) for the layout.

The vendor U-Boot tries to boot Android first, and falls back to distro boot,
which finds `boot.scr` on the bootable `nerves_boot` FAT partition. The
vendor U-Boot's own environment isn't usable, so
[uboot/boot.cmd](uboot/boot.cmd) keeps the Nerves A/B metadata in a raw U-Boot
environment block at sector 73728. It does the usual Nerves validation and
revert logic there.

The frame has no accessible serial console, so the boot script also counts
boots that never reach userspace. After three of them, the next boot drops
into Rockchip loader mode (rockusb) so `rkdeveloptool` can reflash it. erlinit
resets the counter once the root filesystem is up.

## Getting into the frame

The USB-C port is the OTG port. Use a USB-A-to-C cable; C-to-C doesn't
enumerate.

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

Not tested yet. The plan is to boot the vendor U-Boot into mass-storage mode
(`reboot ums`), and run `fwup` against the eMMC from the host. `fwup` only
writes the GPT and the Nerves partitions, so the boot chain is safe.
