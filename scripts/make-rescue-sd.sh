#!/usr/bin/env bash
# Build a microSD card image that makes the vendor U-Boot put the eMMC into
# Rockchip loader mode (rockusb), for when the eMMC boots something that
# hangs. Distro boot checks the card before the eMMC.
#
# The stock idbloader is also copied to sector 64. The vendor U-Boot's
# rkimg_bootdev switches its boot device to the card when `rkimgtest mmc 1`
# finds an IDB there, which is a second way for the card to take over.
#
#   scripts/make-rescue-sd.sh            -> .build/rescue-sd.img
#   sudo dd if=.build/rescue-sd.img of=/dev/sdX bs=1M conv=fsync
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=$REPO/.build
IMG=$OUT/rescue-sd.img
BACKUP=${BACKUP:-$REPO/backups/unit1/parts}
PART_START=32768          # sectors (16 MiB, past the idbloader copy)
PART_SIZE=$((63 * 2048))  # sectors (63 MiB)

mkdir -p "$OUT"
python3 -I "$REPO/scripts/rk-images.py" script "$REPO/scripts/rescue-sd/boot.cmd" "$OUT/rescue-boot.scr"

rm -f "$OUT/rescue-fat.img"
mkfs.vfat -n RESCUE -C "$OUT/rescue-fat.img" $((PART_SIZE / 2)) >/dev/null
mcopy -i "$OUT/rescue-fat.img" "$OUT/rescue-boot.scr" ::boot.scr

rm -f "$IMG"
truncate -s $(((PART_START + PART_SIZE) * 512)) "$IMG"
# One bootable FAT32 (LBA) partition; distro boot only scans bootable ones
printf 'label: dos\nstart=%d, size=%d, type=c, bootable\n' $PART_START $PART_SIZE | sfdisk -q "$IMG"
dd if="$OUT/rescue-fat.img" of="$IMG" bs=512 seek=$PART_START conv=notrunc status=none
# Stock idbloader (sectors 64-16383 of the eMMC) from the backup
{ zcat "$BACKUP/00-gpt-idbloader.img.gz" || true; } | tail -c +$((64 * 512 + 1)) | head -c $(((16384 - 64) * 512)) > "$OUT/idbloader.bin"
dd if="$OUT/idbloader.bin" of="$IMG" bs=512 seek=64 conv=notrunc status=none
rm -f "$OUT/idbloader.bin"
rm -f "$OUT/rescue-fat.img"

sfdisk -l "$IMG" | tail -2
mdir -i "$IMG@@$((PART_START * 512))"
