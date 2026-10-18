#!/usr/bin/env bash
# Install a Nerves .fw on a FRAME156 that's in Rockchip loader mode, using
# rkdeveloptool (no root needed with the udev rule from the README).
#
#   scripts/install-rockusb.sh path/to/firmware.fw
#
# fwup writes the "complete" task into a sparse image the size of the eMMC,
# and only the regions fwup touches are sent to the frame. Everything below
# sector 73728 except the GPT and the bootloader message at the start of
# misc (idbloader, uboot, trust, resource) is never written. The primary
# GPT goes last, so an interrupted install never leaves a Nerves partition
# table pointing at missing data.
#
# Get into loader mode with `adb reboot loader` from Android, or by holding
# the power button while plugging in power with the USB-C cable connected.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
FW=${1:?usage: $0 firmware.fw}
WORK=$REPO/.build/install
DISK_SECTORS=61063168

# Must match fwup_include/fwup-common.conf
MISC_START=32768
ENV_START=73728
ROOTFS_A_START=339968
ROOTFS_B_START=1388544
APP_START=2437120
BACKUP_GPT_START=$((DISK_SECTORS - 33))

rkdeveloptool ld 2>/dev/null | grep -q Loader || {
  echo "The frame isn't in loader mode" >&2
  exit 1
}

mkdir -p "$WORK"
IMG=$WORK/emmc.img
rm -f "$IMG"
truncate -s $((DISK_SECTORS * 512)) "$IMG"
fwup -a -q -d "$IMG" -i "$FW" -t complete --unsafe

# The rootfs is the largest file in the .fw; round up to whole sectors
ROOTFS_BYTES=$(unzip -l "$FW" data/rootfs.img | awk '/data\/rootfs.img/ {print $1}')
ROOTFS_SECTORS=$(( (ROOTFS_BYTES + 511) / 512 ))
MAIN_END=$((ROOTFS_A_START + ROOTFS_SECTORS))

extract() { # name start count
  dd if="$IMG" of="$WORK/$1.bin" bs=512 skip="$2" count="$3" status=none
}
extract misc $MISC_START 4
extract main $ENV_START $((MAIN_END - ENV_START))
extract rootfs-b-head $ROOTFS_B_START 256
extract app-head $APP_START 256
extract gpt-backup $BACKUP_GPT_START 33
extract gpt-primary 0 34

write() { # name start
  echo "Writing $1 at sector $2"
  rkdeveloptool wl "$2" "$WORK/$1.bin" >/dev/null
}
write main $ENV_START
write misc $MISC_START
write rootfs-b-head $ROOTFS_B_START
write app-head $APP_START
write gpt-backup $BACKUP_GPT_START
write gpt-primary 0

# The vendor rockusb only allows reads below 32 MiB, which covers the GPT
rkdeveloptool rl 0 $((34 * 512)) "$WORK/verify.bin" >/dev/null
if cmp -s "$WORK/verify.bin" "$WORK/gpt-primary.bin"; then
  echo "Installed. Reboot with: rkdeveloptool rd"
else
  echo "GPT readback mismatch" >&2
  exit 1
fi
rm -f "$IMG" "$WORK"/*.bin
