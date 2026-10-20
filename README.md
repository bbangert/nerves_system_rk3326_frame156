# Nerves system for the Pastigio FRAME156

A [Nerves](https://nerves-project.org) system for the Pastigio FRAME156, a
15.6" Frameo digital photo frame built on the Rockchip RK3326. It turns the
frame into an [Elixir](https://elixir-lang.org) device: a 1920x1080 touch
display with GPU acceleration, audio, Wi-Fi, and A/B firmware updates over
the network that fall back on their own if new firmware fails to start.

This repository contains the base system image: a mainline Linux kernel and
device tree, the Buildroot root filesystem (`nerves_system_br`), Mesa with
the Panfrost GPU driver, and the boot and update logic needed to run Nerves
under the frame's stock Rockchip bootloader, which is kept as-is.

**Status:** bring-up. Everything in the hardware table below has been
verified on a real frame, except that Wi-Fi has only been seen scanning
(joining a network is untested) and the USB-A port is untested.

## Using

Add the system as a dependency of your Nerves project and pick a target
name for it:

```elixir
# mix.exs
@all_targets [:frame156]

{:nerves_system_rk3326_frame156,
 github: "bbangert/nerves_system_rk3326_frame156", runtime: false, targets: :frame156}
```

```bash
export MIX_TARGET=frame156
mix deps.get
mix firmware
```

Prebuilt system artifacts are published on the GitHub releases page and
downloaded automatically by `mix deps.get`.

The system ships Erlang/OTP 29, so your project needs Elixir 1.20 or later.
The first install goes over USB in Rockchip loader mode (see
[Installing](#installing)); after that, `mix upload` updates the frame over
the network.

The [`example/`](example) directory is a complete Nerves project for this
system, with SSH, Wi-Fi and the accelerometer set up.

## Hardware overview

| Peripheral    | Chip                      | Bus          | Address | Linux device |
|---------------|---------------------------|--------------|---------|--------------|
| SoC           | Rockchip RK3326, 4x Cortex-A35 | —       | —       | cpufreq 600 MHz–1.3 GHz (`schedutil`) |
| Memory        | 1 GB DDR3                 | —            | —       | `/sys/class/devfreq/dmc` (194/328/400 MHz) |
| Storage       | 32 GB eMMC                | eMMC         | —       | `/dev/mmcblk0` |
| Display       | 1920x1080 eDP panel via Lontium LT8911EXB | MIPI DSI, I2C2 | 0x29 | `/dev/dri/card0` (rockchip-drm) |
| Backlight     | PWM                       | PWM1         | —       | `/sys/class/backlight/backlight/` |
| Touchscreen   | Silead GSL3676            | I2C1         | 0x40    | `/dev/input/event*` (`silead_ts`) |
| GPU           | Mali-G31 MP1              | —            | —       | `/dev/dri/card1` (panfrost) |
| PMIC, audio, RTC | Rockchip RK809         | I2C0, I2S1   | 0x20    | ALSA card `rk809`, `/dev/rtc0` |
| Speaker amp   | GPIO-enabled amplifier    | GPIO3_C3     | —       | part of the `rk809` card |
| Wi-Fi         | Rockchip RK915, 2.4 GHz only | SDIO      | —       | `wlan0` |
| Accelerometer | MC3419-like               | I2C1         | 0x4c    | `/dev/i2c-1` (no kernel driver) |
| Power button  | RK809 power key           | —            | —       | `/dev/input/event*` (`rk805 pwrkey`) |
| Watchdog      | DesignWare WDT            | —            | —       | `/dev/watchdog0` |
| USB-C         | OTG, device mode          | USB 2.0      | —       | `usb0` (CDC ECM), `ttyGS0` |
| USB-A         | Host                      | USB 2.0      | —       | — |

The board has no Bluetooth. The IR receiver and PIR motion sensor
connectors aren't populated. Some units have a 1366x768 panel, which needs
its own panel timings and isn't supported yet.

## Display

### Backlight

```elixir
# Set brightness (0–255)
File.write!("/sys/class/backlight/backlight/brightness", "128")

# Turn the backlight off
File.write!("/sys/class/backlight/backlight/brightness", "0")
```

### GPU

Mesa provides EGL and OpenGL ES 3.1 on the Mali-G31 through the Panfrost
driver. Rendering goes through DRM/KMS on `/dev/dri/card0`; `kmscube` is
included as a quick check:

```elixir
System.cmd("kmscube", ["-D", "/dev/dri/card0"])
```

### Display planes

The display controller has three planes, stacked in a fixed order (an
immutable `zpos` property): the primary plane (win0, scales, RGB and YUV),
an overlay (win1) and a cursor plane (win2). The overlay and cursor planes
take RGB only, can't scale, and have an `alpha` property, so the display
controller can blend a full-screen image over the primary plane at the
panel's 60 Hz with no GPU work (a photo crossfade, for example).

No plane can rotate or mirror (neither can stock's driver), so when the
frame stands in portrait or upside down, rotate the content itself: the GPU
for the UI, and photos as they're prepared.

### Memory clock

The loader starts the DDR3 at 332 MHz. Stock Android runs it at 400 MHz,
and full-screen GPU blends go noticeably faster there. The kernel's DDR
driver starts with the `userspace` governor and doesn't change the rate on
its own, so every boot starts at 332 MHz. To switch:

```elixir
File.write!("/sys/class/devfreq/dmc/userspace/set_freq", "400000000")
```

The example app does this once the firmware has validated
(`FrameExample.DdrRate`). 400 MHz is the highest rate stock enables on this
board; the driver offers nothing above it.

## Touchscreen

The Silead GSL3676 needs a firmware file that can't be redistributed, so
it isn't part of the prebuilt system. Extract it from a backup of the frame's
stock Android kernel (see [docs/bring-up.md](docs/bring-up.md)):

```bash
scripts/extract-touch-fw.py backups/<unit>/parts/p5-kernel.img.gz \
    gsl3676.fw
```

Put the file in your project at `rootfs_overlay/lib/firmware/silead/gsl3676.fw`.
The script checks the result against the known-good firmware's hash.

The touchscreen then shows up as a standard multitouch input device named
`silead_ts`. It reports positions from 0–1792 on X and 0–1152 on Y, already
oriented to the panel; scale them to the 1920x1080 display using the ranges
the device advertises. Read it with any evdev library, or try it out with
`evtest`.

## Audio

The RK809 codec drives the speaker through an external amplifier, which
the kernel switches on while audio plays. ALSA tools are included:

```elixir
# Set the volume
System.cmd("amixer", ["sset", "Master", "80%"])

# Play a test tone
System.cmd("speaker-test", ["-t", "sine", "-f", "440", "-l", "1"])

# Play a WAV file
System.cmd("aplay", ["/data/chime.wav"])
```

## Wi-Fi

The RK915 is a 2.4 GHz-only 802.11n chip, driven by the community
[rk915](https://github.com/rei512/rk915) mac80211 driver. Configure it with
[VintageNet](https://hexdocs.pm/vintage_net):

```elixir
VintageNetWiFi.quick_configure("my-ssid", "my-password")
```

The chip has no burned-in MAC address. The system derives a stable,
locally administered one from the eMMC's ID at boot, so the address
survives firmware updates.

## Sensors

### Accelerometer

An accelerometer sits on I2C1 at 0x4c. It answers like the mCube MC3419
family, which mainline Linux has no driver for, so read it from Elixir with
[`circuits_i2c`](https://hex.pm/packages/circuits_i2c):

```elixir
{:ok, i2c} = Circuits.I2C.open("i2c-1")

# Wake it up (mode register 0x07)
:ok = Circuits.I2C.write(i2c, 0x4C, <<0x07, 0x01>>)

# X/Y/Z, 16-bit little-endian, about 16384 counts per g
{:ok, <<x::little-signed-16, y::little-signed-16, z::little-signed-16>>} =
  Circuits.I2C.write_read(i2c, 0x4C, <<0x0D>>, 6)

{x / 16384, y / 16384, z / 16384}
```

Standing on its stand in landscape, the frame reads about -1 g on Y.
`FrameExample.Orientation` in the example app turns this into an orientation.

### Temperature

```elixir
# SoC and GPU temperatures in millidegrees Celsius
File.read!("/sys/class/thermal/thermal_zone0/temp")  # soc-thermal
File.read!("/sys/class/thermal/thermal_zone1/temp")  # gpu-thermal
```

## Power button

The power button is an input device named `rk805 pwrkey` that sends
`KEY_POWER`. Nothing acts on it by default, so your app decides what a press
does.

## RTC

The RK809 PMIC provides the real-time clock at `/dev/rtc0`. It isn't set
from NTP yet, so until the network is up it reads 2017 at boot.

## Serial number

`Nerves.Runtime.serial_number/0` returns the eMMC's 8-digit product serial
number. To use your own, set `nerves_serial_number` in the U-Boot
environment block:

```elixir
Nerves.Runtime.KV.put("nerves_serial_number", "frame-0001")
```

The new serial number takes effect at the next boot.

## Installing

The first install writes the eMMC over USB while the frame is in Rockchip
loader mode. The stock bootloader (idbloader, U-Boot, trust) and the factory
`resource` partition are never written, so the frame can always be restored
to Android.

You need:

- a **USB-A-to-C** cable into the frame's USB-C port (C-to-C doesn't
  enumerate)
- the frame's **own power supply** plugged in as well (laptop USB power alone
  browns the board out once Nerves starts, which looks like a boot loop)
- [`rkdeveloptool`](https://github.com/rockchip-linux/rkdeveloptool), with a
  udev rule for Rockchip devices, for example in
  `/etc/udev/rules.d/60-rockchip.rules`:

  ```
  SUBSYSTEM=="usb", ATTRS{idVendor}=="2207", MODE="0660", TAG+="uaccess"
  ```

**Back up the frame first.** `scripts/backup.sh` copies every eMMC partition
except userdata over ADB and verifies each one (see
[docs/bring-up.md](docs/bring-up.md)).

Then get into loader mode, either with `adb reboot loader` from Android
(enable Frameo **Settings → About → Beta → ADB Access**), or by holding the
power button while plugging in power with the USB cable connected, and run:

```bash
scripts/install-rockusb.sh _build/frame156_dev/nerves/images/my_app.fw
rkdeveloptool rd
```

Over the USB-C cable the frame is a network device (VintageNetDirect), so
`ssh nerves.local` works once it has booted.

## Firmware updates

After the first install, update over SSH as with any Nerves device:

```bash
mix upload nerves.local
```

Updates are A/B. New firmware is tried once; `nerves_runtime`'s
`StartupGuard` marks it good after your app starts. If it panics, hangs
(the watchdog resets it) or loses power before that, the frame boots the
previous firmware again. Enable the guard in your project's config:

```elixir
config :nerves_runtime, startup_guard_enabled: true
```

To get back into loader mode from a running system:

```elixir
File.write!("/run/reboot-param", "loader")
Nerves.Runtime.reboot()
```

See [docs/design.md](docs/design.md) for how booting and updates work under
the stock bootloader, and [docs/recovery.md](docs/recovery.md) for getting a
stuck frame back, including restoring Android with
`scripts/factory-restore.sh`.

## Building the system

Prebuilt artifacts come from GitHub releases, so most projects never build
the system. To build it from source (Linux only, about 30 GB of disk):

```bash
mix deps.get
mix compile
```

Projects that depend on a local checkout build it automatically. Use a
`path:` dependency with `nerves: [compile: true]`, as the example app does.

CI builds the system on every push. Pushing a `vX.Y.Z` tag that matches
`VERSION` drafts a GitHub release with the artifact and the matching
`CHANGELOG.md` section.

## Linux kernel

Kernel: Linux 7.1.2 (mainline)
Config: [`linux/linux-7.1.config`](linux/linux-7.1.config) (ROCKNIX's RK3326
config) plus [`linux/nerves.fragment`](linux/nerves.fragment)
Device tree: [`dts/rk3326-pastigio-frame156.dts`](dts/rk3326-pastigio-frame156.dts)

Patches in [`patches/linux/`](patches/linux):

- `0001` panel entries for the FRAME156's eDP panel
- `0002`, `0003` dwc2 USB gadget fixes
- `0004` early watchdog option for bring-up
- `0005` Lontium LT8911EXB DSI-to-eDP bridge driver
- `0006` built-in device tree override, since the stock U-Boot only copes
  with the stock device tree
- `0007` lets the RK809 skip its PMIC restart, so reboot modes survive
- `0008` SDIO quirks for the RK915 Wi-Fi
- `0009` exports the PX30/RK3326 I2S1 source clock, so audio can run it at
  600 MHz
- `0010`, `0011` PX30 DDR rate scaling through BL31 (from ROCKNIX), with
  the board's stock DDR timings
- `0012` DDR3 support for the DDR monitor (DFI)
- `0013` the DDR driver starts with the `userspace` governor, so nothing
  changes the rate at boot
- `0014` keeps a power domain's QoS defaults on its first power-up instead
  of zeroing them (this gave the GPU bus priority 0)
- `0015` plane alpha and zpos for the PX30 display controller

[`patches/buildroot/`](patches/buildroot) builds Mesa's Panfrost driver
without LLVM and Clang for the target.

## Further reading

- [docs/hardware.md](docs/hardware.md): everything learned from the stock
  firmware, peripheral by peripheral
- [docs/design.md](docs/design.md): boot flow, partition layout and A/B
  updates
- [docs/recovery.md](docs/recovery.md): recovering a frame that won't boot
- [docs/bring-up.md](docs/bring-up.md): ADB access, backups, and testing
  kernels without touching the boot partitions

## License

The system is licensed under GPL-2.0 (see `mix.exs`), like the kernel
patches and Buildroot it builds on.
