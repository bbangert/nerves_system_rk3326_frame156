#!/bin/sh

set -e

FWUP_CONFIG=$NERVES_DEFCONFIG_DIR/fwup.conf

if ! command -v mix > /dev/null 2>&1; then
    echo "ERROR: Elixir/Mix is required to generate fwup.conf but was not found on your PATH."
    echo "Please install Elixir: https://elixir-lang.org/install.html"
    exit 1
fi

# The vendor U-Boot boots Android boot images: slot A from the "boot"
# partition, slot B from "recovery" (see fwup_include/fwup-common.conf).
# Each image is the kernel (which carries our device tree), an empty
# initramfs, a command line pointing at that slot's root filesystem, and a
# Rockchip resource image with the *stock* device tree as the second stage.
# U-Boot builds its own driver model from that device tree (its PMIC
# driver needs it), and only falls back to the resource partition when the
# boot image header is invalid: with a valid header and no second stage it
# runs without a PMIC driver and drops into loader or recovery mode.
#
# U-Boot rewrites the first console= to ttyFIQ0, hence the sacrificial
# first one, and appends init=/init (rootfs_overlay/init links to erlinit).
python3 -I "$NERVES_DEFCONFIG_DIR/scripts/rk-resource.py" pack \
    "$BINARIES_DIR/boot-resource.img" "$NERVES_DEFCONFIG_DIR/board/rk-kernel.dtb"
CMDLINE_COMMON="rootfstype=squashfs rootwait ro console=ttyFIQ0 console=tty1 console=ttyGS0,115200 consoleblank=0"
for slot in a b; do
    case $slot in
        a) partuuid=a1b2c3d4-0a0a-4e5f-8a6b-7c8d9e0f1a2b ;;
        b) partuuid=b1b2c3d4-0b0b-4e5f-8a6b-7c8d9e0f1a2b ;;
    esac
    python3 -I "$NERVES_DEFCONFIG_DIR/scripts/rk-images.py" bootimg \
        "$BINARIES_DIR/Image" "root=PARTUUID=$partuuid $CMDLINE_COMMON" \
        "$BINARIES_DIR/boot-$slot.img" "" "$BINARIES_DIR/boot-resource.img"
done

(cd "$NERVES_DEFCONFIG_DIR" && ELIXIR_ERL_OPTIONS="+fnu" mix generate_fwup_conf)

# Run the common post-image processing for nerves
$BR2_EXTERNAL_NERVES_PATH/board/nerves-common/post-createfs.sh $TARGET_DIR $FWUP_CONFIG
