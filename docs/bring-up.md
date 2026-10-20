# Bring-up notes

Working with the stock Android firmware: getting in over USB, backing it
up, and testing kernels without touching the boot partitions.

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

Keep the backup: once Nerves is installed, it's the only copy of the stock
kernel, which is where the touchscreen firmware comes from (see the
README's Touchscreen section).

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
