#!/usr/bin/env bash
# Put a FRAME156 back to its stock firmware from a scripts/backup.sh backup
# (taken with --with-userdata), using rkdeveloptool in loader or mask-ROM
# mode. Only writes, since the vendor rockusb refuses reads past 32 MiB.
#
#   scripts/factory-restore.sh backups/<serial> [--with-idbloader]
#
# SKIP="p16-userdata ..." leaves the named images out, for partitions known
# to be unchanged (Nerves never writes Android's userdata area beyond the
# app partition header, which lies in the system partition).
#
# Writes every partition image at its stock offset, then the backup GPT at
# the end of the disk, then the primary GPT. The idbloader (sectors
# 64-16383) is only rewritten with --with-idbloader, because Nerves never
# touches it and an interrupted write there is the one thing that would
# force mask-ROM mode.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
DIR=${1:?usage: $0 backups/<serial> [--with-idbloader]}
WITH_IDB=0
[ "${2:-}" = "--with-idbloader" ] && WITH_IDB=1
PARTS=$DIR/parts
WORK=$REPO/.build/factory-restore
LOADER=$REPO/.build/maskrom/rk3326_loader_v2.12.140.bin

# Stock layout: image name, start sector (from the stock GPT)
LAYOUT="p1-uboot 16384
p2-trust 24576
p3-misc 32768
p4-resource 40960
p5-kernel 73728
p6-boot 139264
p7-recovery 217088
p8-backup 360448
p9-security 589824
p10-cache 598016
p11-system 1384448
p12-metadata 4530176
p13-vendor 4562944
p14-oem 5349376
p15-frp 5611520
p16-userdata 5612544"

for f in SUMS.sha256sum 00-gpt-idbloader.img.gz gpt-backup-reconstructed.bin; do
  [ -f "$PARTS/$f" ] || { echo "Missing $PARTS/$f" >&2; exit 1; }
done
while read -r name _; do
  [ -f "$PARTS/$name.img.gz" ] || { echo "Missing $PARTS/$name.img.gz (back up with --with-userdata)" >&2; exit 1; }
done <<< "$LAYOUT"

mode=$(rkdeveloptool ld 2>/dev/null || true)
if echo "$mode" | grep -q Maskrom; then
  echo "Mask-ROM mode: loading the RK3326 loader"
  rkdeveloptool db "$LOADER" >/dev/null
  sleep 3
elif ! echo "$mode" | grep -q Loader; then
  echo "The frame isn't in loader or mask-ROM mode (adb reboot loader)" >&2
  exit 1
fi

mkdir -p "$WORK"
# Decompress, check against the backup's checksums, and write one image
restore() { # name start
  local img=$WORK/$1.img
  { zcat "$PARTS/$1.img.gz" || true; } > "$img"
  want=$(grep " $1.img\$" "$PARTS/SUMS.sha256sum" | cut -d' ' -f1)
  got=$(sha256sum "$img" | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "$1: checksum mismatch, not writing" >&2; exit 1; }
  echo "Writing $1 at sector $2"
  rkdeveloptool wl "$2" "$img" >/dev/null
  rm -f "$img"
}

while read -r name start; do
  case " ${SKIP:-} " in
    *" $name "*) echo "Skipping $name"; continue ;;
  esac
  restore "$name" "$start"
done <<< "$LAYOUT"

if [ "$WITH_IDB" = 1 ]; then
  restore 00-gpt-idbloader 0
else
  echo "Writing the primary GPT"
  { zcat "$PARTS/00-gpt-idbloader.img.gz" || true; } | head -c $((34 * 512)) > "$WORK/gpt-primary.bin"
  # Write the backup GPT first, so both copies are never inconsistent at once
  rkdeveloptool wl 61063135 "$PARTS/gpt-backup-reconstructed.bin" >/dev/null
  rkdeveloptool wl 0 "$WORK/gpt-primary.bin" >/dev/null
fi
[ "$WITH_IDB" = 1 ] && rkdeveloptool wl 61063135 "$PARTS/gpt-backup-reconstructed.bin" >/dev/null

echo "Factory restore written. Reboot with: rkdeveloptool rd"
