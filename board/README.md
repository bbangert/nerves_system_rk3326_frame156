# board/

`rk-kernel.dtb` is the stock Android device tree from unit 1's
`resource` partition (firmware FrameO.DP105F.v2026010414). It goes into the
Rockchip resource image in each Nerves boot image, because the vendor U-Boot
builds its own drivers (PMIC, logo display) from the boot image's device tree
and misbehaves without one. The Linux kernel ignores it and uses its built-in
device tree (dts/).

Units with other panels have their own stock device tree (for example
unit 2's 1366x768 panel). U-Boot only uses the panel timings for its boot
logo, so the wrong ones at worst garble the logo before Linux takes over.
