# Changelog

## v0.1.0

Initial release.

* Linux 7.1.2 (mainline) with the ROCKNIX RK3326 config
* Boots through the stock Rockchip U-Boot, with A/B firmware updates that
  fall back automatically if the new firmware doesn't validate
* Display (1920x1080 eDP through the Lontium LT8911EXB bridge), backlight,
  touchscreen (Silead GSL3676), GPU (Mali-G31, Panfrost + Mesa), audio
  (RK809), Wi-Fi (RK915, 2.4 GHz), RTC, power key and watchdog
