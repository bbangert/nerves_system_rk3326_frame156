# FRAME156 rescue card: put the eMMC into Rockchip loader mode.
#
# The vendor U-Boot's distro boot tries the microSD card (mmc1) before the
# eMMC (mmc0), so this runs even when the eMMC holds a boot.scr that hangs.
# Use whichever MMC device this script didn't come from, in case the
# numbering is the other way round.

if test "${devnum}" = "1"; then
    setenv rescue_dev 0
else
    setenv rescue_dev 1
fi
echo "FRAME156 rescue: rockusb on mmc ${rescue_dev}"
rockusb 0 mmc ${rescue_dev}
reset
