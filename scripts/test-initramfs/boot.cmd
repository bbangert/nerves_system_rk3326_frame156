# Bring-up boot script: boots the test kernel and busybox initramfs from the
# same FAT partition (see scripts/bringup-distroboot.sh). Run by the vendor
# U-Boot's distro boot, exactly like the real Nerves boot.scr.

echo "FRAME156 bring-up boot from ${devtype} ${devnum}:${distro_bootpart}"
setenv bootargs "console=tty1 console=ttyGS0,115200 loglevel=7"

fatload ${devtype} ${devnum}:${distro_bootpart} 0x08300000 frame156.dtb
fatload ${devtype} ${devnum}:${distro_bootpart} 0x00280000 Image
fatload ${devtype} ${devnum}:${distro_bootpart} 0x0a200000 uInitrd
booti 0x00280000 0x0a200000 0x08300000

# booti only returns on failure
echo "booti failed; entering Rockchip loader mode"
rockusb 0 ${devtype} ${devnum}
reset
