#!/usr/bin/env bash
# Boot test kernels through the vendor U-Boot's distro boot (the same path
# Nerves uses) while keeping the stock Android partition table and userdata.
#
#   scripts/bringup-distroboot.sh prepare   build .build/bringup/cache-fat.img
#   scripts/bringup-distroboot.sh install   frame in Android (ADB, root)
#   scripts/bringup-distroboot.sh restore   frame in loader mode: undo
#
# install:
#   - zeroes the first 2 KiB of the stock kernel, boot and recovery
#     partitions, so U-Boot's Android and Rockchip boot attempts fail
#   - marks the cache partition (p10) legacy-bootable in the primary GPT
#   - writes a FAT filesystem with boot.scr, the kernel, device tree and
#     initramfs from scripts/build-test-kernel.sh to the cache partition
# Every write is read back and checked. The backup GPT at the end of the
# disk is left alone (32-bit dd on Android can't seek there); it stays a
# self-consistent copy of the stock table.
#
# restore only writes, using the ADB backup, because the vendor rockusb
# refuses reads past 32 MiB (writes work). It puts back the stock GPT, the
# kernel and boot headers, and the whole recovery and cache partitions.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK=$REPO/.build/bringup
TEST=$REPO/.build/test
BACKUP=${BACKUP:-$REPO/backups/unit1/parts}

# Stock layout (512-byte sectors)
KERNEL_START=73728
BOOT_START=139264
RECOVERY_START=217088
CACHE_START=598016
CACHE_PART=10

asu() { adb exec-out "su -c '$*'" | tr -d '\r'; }
wl() { rkdeveloptool wl "$1" "$2" >/dev/null; }

require_loader() {
  local mode
  mode=$(rkdeveloptool ld 2>/dev/null || true)
  if echo "$mode" | grep -q Maskrom; then
    # Mask ROM only runs code it's given: load the usbplug loader first
    echo "Frame is in mask-ROM mode; loading the RK3326 loader"
    rkdeveloptool db "$REPO/.build/maskrom/rk3326_loader_v2.12.140.bin" >/dev/null
    sleep 3
    mode=$(rkdeveloptool ld 2>/dev/null || true)
  fi
  echo "$mode" | grep -qE 'Loader|Maskrom' || {
    echo "The frame isn't in loader or mask-ROM mode (adb reboot loader)" >&2
    exit 1
  }
}

# The stock primary GPT (protective MBR, header and entries)
stock_gpt() { { zcat "$BACKUP/00-gpt-idbloader.img.gz" || true; } | head -c $((34 * 512)); }

prepare() {
  [ -f "$TEST/Image" ] || { echo "Run scripts/build-test-kernel.sh first" >&2; exit 1; }
  mkdir -p "$WORK"
  python3 -I "$REPO/scripts/rk-images.py" script "$REPO/scripts/test-initramfs/boot.cmd" "$WORK/boot.scr"
  python3 -I "$REPO/scripts/rk-images.py" ramdisk "$TEST/initramfs.cpio.gz" "$WORK/uInitrd"
  rm -f "$WORK/cache-fat.img"
  mkfs.vfat -n FRAME156 -C "$WORK/cache-fat.img" $((64 * 1024)) >/dev/null
  mcopy -i "$WORK/cache-fat.img" "$WORK/boot.scr" ::boot.scr
  mcopy -i "$WORK/cache-fat.img" "$TEST/Image" ::Image
  mcopy -i "$WORK/cache-fat.img" "$TEST/rk3326-pastigio-frame156.dtb" ::frame156.dtb
  mcopy -i "$WORK/cache-fat.img" "$WORK/uInitrd" ::uInitrd
  mdir -i "$WORK/cache-fat.img"
}

install() {
  [ -f "$WORK/cache-fat.img" ] || { echo "Run '$0 prepare' first" >&2; exit 1; }
  [ "$(adb get-state 2>/dev/null)" = device ] || { echo "No ADB device" >&2; exit 1; }
  [ "$(asu id -u)" = 0 ] || { echo "su didn't give root" >&2; exit 1; }

  # Only patch a disk that still has the stock partition table
  stock=$(stock_gpt | sha256sum | cut -d' ' -f1)
  current=$(asu "dd if=/dev/block/mmcblk2 bs=512 count=34 2>/dev/null | sha256sum" | cut -d' ' -f1)
  [ "$current" = "$stock" ] || { echo "The GPT isn't the stock one; not writing anything" >&2; exit 1; }

  stock_gpt > "$WORK/gpt-primary.bin"
  python3 -I "$REPO/scripts/rk-images.py" gpt-bootable "$WORK/gpt-primary.bin" $CACHE_PART on
  head -c 2048 /dev/zero > "$WORK/zero-2k.bin"

  adb push "$WORK/cache-fat.img" "$WORK/gpt-primary.bin" "$WORK/zero-2k.bin" /data/local/tmp/ >/dev/null
  # Android must not write to cache while we replace it
  asu "umount /cache 2>/dev/null || mount -o remount,ro /cache 2>/dev/null; true"
  echo "Writing cache FAT filesystem"
  asu "dd if=/data/local/tmp/cache-fat.img of=/dev/block/mmcblk2p10 bs=1048576 2>/dev/null"
  echo "Disabling Android kernel, boot and recovery"
  for p in 5 6 7; do
    asu "dd if=/data/local/tmp/zero-2k.bin of=/dev/block/mmcblk2p$p bs=2048 count=1 2>/dev/null"
  done
  echo "Marking cache bootable"
  asu "dd if=/data/local/tmp/gpt-primary.bin of=/dev/block/mmcblk2 bs=512 count=34 2>/dev/null; sync; echo 3 > /proc/sys/vm/drop_caches"

  check() { # what device-command expected-file
    local got want
    got=$(asu "$2 2>/dev/null | sha256sum" | cut -d' ' -f1)
    want=$(sha256sum "$3" | cut -d' ' -f1)
    if [ "$got" = "$want" ]; then echo "  ok: $1"; else echo "  MISMATCH: $1" >&2; return 1; fi
  }
  fat_blocks=$(($(stat -c %s "$WORK/cache-fat.img") / 1048576))
  check "cache FAT" "dd if=/dev/block/mmcblk2p10 bs=1048576 count=$fat_blocks" "$WORK/cache-fat.img"
  for p in 5 6 7; do
    check "p$p header" "dd if=/dev/block/mmcblk2p$p bs=2048 count=1" "$WORK/zero-2k.bin"
  done
  check "primary GPT" "dd if=/dev/block/mmcblk2 bs=512 count=34" "$WORK/gpt-primary.bin"
  asu "rm -f /data/local/tmp/cache-fat.img /data/local/tmp/gpt-primary.bin /data/local/tmp/zero-2k.bin"
  echo "Installed. Reboot with: adb reboot"
}

restore() {
  require_loader
  mkdir -p "$WORK"
  echo "Restoring the stock GPT"
  stock_gpt > "$WORK/gpt-stock.bin"
  wl 0 "$WORK/gpt-stock.bin"
  echo "Restoring kernel and boot headers"
  { zcat "$BACKUP/p5-kernel.img.gz" || true; } | head -c 2048 > "$WORK/kernel-head.bin"
  { zcat "$BACKUP/p6-boot.img.gz" || true; } | head -c 2048 > "$WORK/boot-head.bin"
  wl $KERNEL_START "$WORK/kernel-head.bin"
  wl $BOOT_START "$WORK/boot-head.bin"
  echo "Restoring recovery and cache"
  zcat "$BACKUP/p7-recovery.img.gz" > "$WORK/recovery.img"
  wl $RECOVERY_START "$WORK/recovery.img"
  zcat "$BACKUP/p10-cache.img.gz" > "$WORK/cache.img"
  wl $CACHE_START "$WORK/cache.img"
  rm -f "$WORK/recovery.img" "$WORK/cache.img"
  echo "Restored. Reboot with: rkdeveloptool rd"
}

case "${1:-}" in
  prepare) prepare ;;
  install) install ;;
  restore) restore ;;
  *) sed -n '2,24p' "$0"; exit 1 ;;
esac
