# Recovering a FRAME156 that won't boot

Use this when the frame shows the "Welcome" logo forever and never appears on
USB: no ADB, no loader mode (`2207:330d`).

## Why it's stuck

A bring-up test (`scripts/bringup-distroboot.sh install`) disabled Android's
boot. It zeroed the first 2 KiB of the `kernel`, `boot` and `recovery`
partitions and booted a test kernel from the `cache` partition. That boot
hangs silently on every power-up. The vendor U-Boot doesn't use the SD
slot, and the serial console isn't wired up.

Nothing important is lost. The Rockchip boot chain and Android's userdata
are untouched, and `backups/unit1/` holds every byte the test changed.

## First: the power-button escape (no tools, proven)

1. Connect the frame's USB-C port to the computer (USB-A-to-C cable).
2. Hold the power button on the back.
3. While holding it, plug in the frame's power. Keep holding for about 5
   seconds.
4. `rkdeveloptool ld` shows `Loader` (`2207:330d`).

This works because the vendor U-Boot's download check includes the RK809
power key, and goes to rockusb when a PC is attached. It needs U-Boot to be
running with a device tree whose PMIC probes: the stock `resource`
partition, or ours with its `gpio0`-`gpio3` aliases. It recovered unit
unit 1 on 2026-10-17.

## If that fails: one of these, once

The board is a C-LINK `CL-RK3326-DP105F V1.3`.

### Option A: mask-ROM mode (fine tweezers, about 2 seconds)

If the RK3326 boot ROM can't read the eMMC at power-on, it waits in
mask-ROM mode on the USB-C port.

1. Connect the frame's USB-C port to the computer (USB-A-to-C cable;
   C-to-C doesn't enumerate).
2. With the frame unpowered, short the **eMMC clock line to ground**. Use a
   test point near the eMMC (the "SCY" BGA chip on the shield side of the
   board, right of the big metal can) if one is labelled `CLK`, `TP` or
   `MASKROM`. Otherwise use the CLK series resistor between the eMMC and
   the SoC.
3. While holding the short, plug in power. Release after about 2 seconds.
4. `rkdeveloptool ld` should print `Maskrom`.

### Option B: serial console (3.3 V USB-TTL adapter)

The board has `TX RX GND` pads below the eMMC, next to the Wi-Fi shield,
and a 4-pin `IR/UART` connector on the other side.

1. Wire adapter GND to GND, adapter RX to board TX, and adapter TX to board
   RX. **Don't connect the adapter's VCC.** Settings: 1500000 baud, 8N1.
2. Hold Ctrl+C in the terminal and power the frame on, to stop U-Boot's
   autoboot (its boot delay is 0).
3. At the `=>` prompt, run `rockusb 0 mmc 0`. The frame appears as
   `2207:330d` (loader mode).

## Then restore Android

From the repo, with the frame in mask-ROM or loader mode:

```sh
scripts/bringup-distroboot.sh restore   # loads the mask-ROM loader if needed
rkdeveloptool rd                        # reboot into Android
```

The restore writes back:

- the stock GPT
- the stock headers of the kernel and boot partitions
- the whole stock recovery and cache partitions

The mask-ROM loader is `.build/maskrom/rk3326_loader_v2.12.140.bin`. It was
built from rockchip-linux/rkbin `RKBOOT/RK3326MINIALL.ini` with
`tools/boot_merger`: DDR v2.12, usbplug v1.42 and miniloader v1.40.

`rkdeveloptool` needs the udev rule from the README.
