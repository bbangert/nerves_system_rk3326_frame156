# Pastigio FRAME156 hardware notes

Everything here comes from the stock Android 8.1 firmware (Frameo
`FrameO.DP105F.v2026010414`), read from a running unit with
`scripts/backup.sh`. The decompiled stock device tree is in
`backups/<serial>/info/live.dts`, and `scripts/annotate-dts.py` turns its
numeric phandles back into labels. GPIO numbers below are
`<bank> <pin>`, so `gpio3 20` is GPIO3_C4.

## SoC and memory

- Rockchip RK3326 (4x Cortex-A35, CPU part `0xd04`), about 1 GB RAM.
- The stock kernel is arm64 (Linux 4.4.138), even though Android
  userspace is 32-bit.
- The stock device tree is based on Rockchip's
  `rockchip,rk3326-evb-ai-va-v11` reference board.

## Storage

- 29.8 GB Samsung eMMC on `emmc` (`dwmmc@ff390000`): 8-bit, HS200 at
  1.8 V, 150 MHz max.
- `sdmmc` (`dwmmc@ff370000`) is enabled in the stock device tree
  (4-bit, UHS). Whether there's a physical card slot isn't confirmed.
- Stock GPT (512-byte sectors):

  | Part | Name     | Start    | Sectors  |
  |------|----------|----------|----------|
  | -    | GPT and idbloader | 0 | 16384 |
  | p1   | uboot    | 16384    | 8192     |
  | p2   | trust    | 24576    | 8192     |
  | p3   | misc     | 32768    | 8192     |
  | p4   | resource | 40960    | 32768    |
  | p5   | kernel   | 73728    | 65536    |
  | p6   | boot     | 139264   | 77824    |
  | p7   | recovery | 217088   | 143360   |
  | p8   | backup   | 360448   | 229376   |
  | p9   | security | 589824   | 8192     |
  | p10  | cache    | 598016   | 786432   |
  | p11  | system   | 1384448  | 3145728  |
  | p12  | metadata | 4530176  | 32768    |
  | p13  | vendor   | 4562944  | 786432   |
  | p14  | oem      | 5349376  | 262144   |
  | p15  | frp      | 5611520  | 1024     |
  | p16  | userdata | 5612544  | to end (61063103) |

## Boot chain (stock, kept as-is)

- The idbloader at sector 64 holds the Rockchip DDR init (`DDR V2.06
  20220317`) and the miniloader.
- `trust` holds BL31 (ARM Trusted Firmware).
- `uboot` holds Rockchip vendor U-Boot 2017.09 (built Jan 4 2026).
  - `bootcmd=boot_android ${devtype} ${devnum};boot_fit;bootrkp;run distro_bootcmd;`
  - `boot_targets=mmc1 mmc0 rknand0 usb0 pxe dhcp`
  - Load addresses: `kernel_addr_r=0x00280000`, `fdt_addr_r=0x08300000`,
    `ramdisk_addr_r=0x0a200000`, `scriptaddr=0x00500000`.
  - Commands include `env import/export` (`-c`, variable lists), `fdt`,
    `fatload`, `booti`, `mmc read/write`, `fastboot`, `ums`,
    `rockusb 0 mmc 0` and `rbrom` (drops to the mask ROM's download mode).
  - Has no `setexpr`, so boot scripts can't do arithmetic.
  - Has no squashfs support, so kernels have to come from a FAT partition.
  - Reads the kernel DTB in `resource` to set up the display for the
    boot logo.
- Reboot modes are set through the PMU GRF (`syscon@ff010000`, offset
  `0x200`):

  | Mode       | Magic        | U-Boot action               |
  |------------|--------------|-----------------------------|
  | normal     | `0x5242c300` | normal boot                 |
  | loader     | `0x5242c301` | rockusb (rkdeveloptool)     |
  | recovery   | `0x5242c303` | recovery                    |
  | fastboot   | `0x5242c309` | Android fastboot over USB   |
  | charge     | `0x5242c30b` | charge animation            |
  | ums        | `0x5242c30c` | eMMC as a USB mass-storage disk |

  From Android: `adb reboot loader`, `adb reboot fastboot`, or
  `adb shell su -c 'reboot ums'`.

## USB

- The USB-C port is the OTG port (`usb20_otg`, dwc2, `dr_mode = "otg"`,
  PHY `u2phy_otg`). ADB, rockusb and fastboot all use it.
- A USB-C-to-C cable from a laptop doesn't enumerate; use USB-A to C.
  The frame probably lacks the CC pull-down resistors.
- The USB-A port is host-only, behind `u2phy_host`, with VBUS from
  `vcc5v0_host` (RK809 SWITCH_REG1).
- USB IDs: ADB `2211:0006` (or `18d1:0006`), rockusb `2207:330d`.

## Power: RK809 on i2c0 at 0x20 (interrupt GPIO0_B2)

| Regulator   | RK809      | Voltage     | Notes          |
|-------------|------------|-------------|----------------|
| vdd_logic   | DCDC_REG1  | 0.95-1.35 V | always on      |
| vdd_arm     | DCDC_REG2  | 0.95-1.35 V | always on      |
| vcc_ddr     | DCDC_REG3  | -           | always on      |
| vcc_3v0     | DCDC_REG4  | 3.0 V       | always on      |
| vcc3v3_sys  | DCDC_REG5  | 3.3 V       | always on      |
| vcc_1v0     | LDO_REG1   | 1.0 V       | always on      |
| vcc1v8_soc  | LDO_REG2   | 1.8 V       | always on      |
| vdd1v0_soc  | LDO_REG3   | 1.0 V       | always on      |
| vcc3v0_pmu  | LDO_REG4   | 3.0 V       | always on      |
| vccio_sd    | LDO_REG5   | 1.8-3.3 V   | always on      |
| vcc_sd      | LDO_REG6   | 3.3 V       | always on      |
| vcc2v8_dvp  | LDO_REG7   | 2.8 V       | always on      |
| vcc1v8_dvp  | LDO_REG8   | 1.8 V       | always on      |
| lcd_vio     | LDO_REG9   | 1.85 V      | always on      |
| vcc5v0_host | SWITCH_REG1| 5 V         | USB-A VBUS     |
| vcc3v3_lcd  | SWITCH_REG2| 3.3 V       | panel power, boot-on |

IO domains: vccio1 `vcc_3v0`, vccio2 `vccio_sd`, vccio3 `vcc1v8_dvp`,
vccio4 `vcc_3v0`, vccio5 `vcc_3v0`; pmuio1/2 `vcc3v0_pmu`.

## Display

- Path: VOP-B → `dsi@ff450000` (4 lanes) → Lontium LT8911EXB on
  **i2c2 at 0x29** → eDP 1920x1080.
- DSI-side timing (stock "panel"): pixel clock 152.6 MHz, hfp 140,
  hbp 140, hsync 40, vfp 20, vbp 30, vsync 10. Flags `0x803` (video,
  burst, LPM), RGB888.
- The stock "panel" is listed as `sitronix,st7703`, `simple-panel-dsi`,
  but it's only a placeholder: its init sequence is DCS `0x11`
  (sleep out, then 120 ms) and `0x29` (display on, then 30 ms).
- LT8911EXB device-tree settings: pclk 128 MHz, hact 1920, vact 1080,
  hbp 138, hfp 140, hs 32, vbp 34, vfp 20, vs 6, 4 MIPI lanes, 2 eDP
  lanes, `color = 1`.
- Pins: `stbyb` is gpio3 20 (GPIO3_C4). The bridge reset and panel
  `cocfg` share gpio3 21 (GPIO3_C5).
- **Verified with mainline 7.1.2 (unit 1, 2026-10-17):** the
  panel shows our console once the bridge is out of reset and programmed.
  - Drive `stbyb` (GPIO3_C4) and reset (GPIO3_C5) high; reset is active-low.
    The bridge doesn't answer on I2C until then. Chip ID at page 0x81
    regs 0x00-0x02 reads `17 05 e0`.
  - Program it with the vendor driver's sequence
    (`scripts/lt8911exb-init.sh`), using the **DSI host's timings**:
    152.6 MHz, h 1920/140/40/140, v 1080/20/10/30, 4 MIPI lanes, 2 eDP
    lanes, 8-bit. With the stock `lontium,*` values (128 MHz, h 138/32,
    v 34/6), the bridge sees the MIPI input but passes no video.
  - `TEST=1` (bridge test pattern) displayed even with the wrong timings,
    which separates eDP problems from MIPI problems.
- The stock kernel configures the bridge over I2C (`LT8911EXB_init`,
  `LT8911EX_link_train`, ...). The vendor U-Boot has no Lontium code. So
  the logo seen after a *warm* reboot is probably the bridge still
  running with the config from the previous kernel. Confirm by
  checking for a logo on a cold power-on.
- Backlight: `pwm1` at 1 kHz (period 1,000,000 ns), enable gpio3 16
  (GPIO3_C0), 256 levels, default 200.
- U-Boot's logo buffer is reserved at `0x3df00000`, size `0x5eec36`.
  That's a 1920x1080 24-bpp BMP plus its 54-byte header, scanned out with
  `logo,ymirror = 1`.

## Wi-Fi and Bluetooth

- Rockchip RK915 on `sdio` (`dwmmc@ff380000`), SDIO ID `0296:5348`,
  out-of-tree `rk915` module in stock Android. The chip is reportedly a
  rebranded Seekwave SV6160.
- Wi-Fi power enable: gpio0 1 (GPIO0_A1). Host wake: gpio0 5 (GPIO0_A5).
  32 kHz clock from RK809 clkout2.
- Bluetooth: on `uart1`, reset gpio0 12 (GPIO0_B4), RTS gpio1 19.

## Other peripherals

- RTC: HYM8563 on i2c1 at 0x51.
- IR receiver on `pwm0` (Rockchip PWM remote).
- Keys: `rockchip,key` on SARADC channel 1.
- Audio: RK809 codec, speaker amp enable gpio3 19.
- The stock device tree also declares a motion sensor (`pir-s18`,
  disabled), and on i2c1, touch controllers (gslX680 at 0x40, ilitek at
  0x41) and accelerometers (sc7a20, mir3da, mc3230). These look like
  leftovers from the reference design and may not be fitted.
- Debug UART: uart2 at `0xff160000` (stock `console=ttyFIQ0`,
  1,500,000 baud). The pads haven't been located.
