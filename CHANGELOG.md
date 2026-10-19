# Changelog

## Unreleased

* DDR rate scaling (PX30 DMC through BL31) with the board's stock DDR
  timings. Starts at the loader's 332 MHz with the `userspace` governor;
  400 MHz (the stock rate) speeds up full-screen GPU blends
* Plane alpha and zpos on the display controller, so the overlay plane can
  crossfade over the primary plane at 60 Hz without the GPU
* Fix power domains zeroing their QoS registers on the first power-up (the
  GPU ran at bus priority 0)
* Example app switches DDR to 400 MHz once the firmware has validated

## v0.1.0

Initial release.

* Linux 7.1.2 (mainline) with the ROCKNIX RK3326 config
* Boots through the stock Rockchip U-Boot, with A/B firmware updates that
  fall back automatically if the new firmware doesn't validate
* Display (1920x1080 eDP through the Lontium LT8911EXB bridge), backlight,
  touchscreen (Silead GSL3676), GPU (Mali-G31, Panfrost + Mesa), audio
  (RK809), Wi-Fi (RK915, 2.4 GHz), RTC, power key and watchdog
