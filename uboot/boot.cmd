# Nerves boot script for the Pastigio FRAME156
#
# The stock vendor U-Boot (2017.09) runs this through distro boot once its
# Android and Rockchip boot attempts fail. Its own environment isn't
# usable, so the Nerves firmware metadata lives in a raw 128 KiB U-Boot
# environment block at sector 73728 (0x12000); see
# fwup_include/fwup-common.conf. This script imports that block, applies
# the A/B validation rules, writes it back, and boots the active slot.
#
# The frame has no serial console, so a kernel that never reaches
# userspace would otherwise leave it stuck. Every boot increments
# nerves_boot_tries, and erlinit resets it (the boot-ok task in
# fwup-ops.conf). After three boots that never got that far, the next
# boot starts rockusb instead, so the frame shows up in loader mode for
# rkdeveloptool.
#
# This U-Boot has no setexpr, so the counter steps through string states.
# Only this script ever leaves it at "0" (when it trips), since userspace
# resets it after boot.scr has already run.

# Keep the distro boot variables we need. Importing the Nerves environment
# with -d replaces the whole environment, which keeps U-Boot's own
# variables out of the Nerves block when it's written back.
env export -t 0x0a300000 devtype devnum distro_bootpart
mmc dev ${devnum}
mmc read 0x0a200000 0x12000 0x100

if env import -d -c 0x0a200000 0x20000; then
    # A/B validation: a firmware that was booted once and never validated
    # gets reverted.
    if test "${nerves_fw_booted}" = "1"; then
        if test "${nerves_fw_validated}" = "0"; then
            if test "${nerves_fw_active}" = "a"; then
                echo "Firmware in A wasn't validated; reverting to B"
                setenv nerves_fw_active b
            else
                echo "Firmware in B wasn't validated; reverting to A"
                setenv nerves_fw_active a
            fi
            setenv nerves_fw_validated 1
        fi
    else
        setenv nerves_fw_booted 1
        if test "${nerves_fw_autovalidate}" = "1"; then
            setenv nerves_fw_validated 1
        fi
    fi

    if test "${nerves_boot_tries}" = "3"; then
        setenv nerves_boot_tries 0
    elif test "${nerves_boot_tries}" = "2"; then
        setenv nerves_boot_tries 3
    elif test "${nerves_boot_tries}" = "1"; then
        setenv nerves_boot_tries 2
    else
        setenv nerves_boot_tries 1
    fi

    env export -c -s 0x20000 0x0a200000
    mmc write 0x0a200000 0x12000 0x100
else
    echo "Nerves environment is missing or corrupt; booting A without saving"
    setenv nerves_fw_active a
fi

env import -t 0x0a300000

if test "${nerves_boot_tries}" = "0"; then
    echo "Too many failed boots; entering Rockchip loader mode"
    rockusb 0 ${devtype} ${devnum}
    reset
fi

if test "${nerves_fw_active}" = "b"; then
    echo "Booting Nerves partition B"
    setenv nerves_root PARTUUID=b1b2c3d4-0b0b-4e5f-8a6b-7c8d9e0f1a2b
else
    echo "Booting Nerves partition A"
    setenv nerves_root PARTUUID=a1b2c3d4-0a0a-4e5f-8a6b-7c8d9e0f1a2b
fi

setenv bootargs "root=${nerves_root} rootfstype=squashfs rootwait ro console=tty1 console=ttyGS0,115200 ${nerves_extra_bootargs}"

fatload ${devtype} ${devnum}:${distro_bootpart} 0x08300000 frame156.${nerves_fw_active}.dtb
fatload ${devtype} ${devnum}:${distro_bootpart} 0x00280000 Image.${nerves_fw_active}
booti 0x00280000 - 0x08300000

# booti only returns on failure
echo "booti failed; entering Rockchip loader mode"
rockusb 0 ${devtype} ${devnum}
reset
