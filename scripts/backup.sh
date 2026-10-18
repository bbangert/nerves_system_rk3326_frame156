#!/usr/bin/env bash
# Back up the eMMC of a Pastigio FRAME156 (RK3326, Android 8.1) over ADB,
# using the stock /system/xbin/su. Read-only on the frame apart from a
# temporary helper in /data/local/tmp.
#
#   scripts/backup.sh [--with-userdata] [OUTDIR]
#
# Re-running skips images that already verify, so it is safe to resume.
set -euo pipefail

WITH_USERDATA=0
OUT=""
for a in "$@"; do
  case "$a" in
    --with-userdata) WITH_USERDATA=1 ;;
    -h | --help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) OUT=$a ;;
  esac
done

command -v adb >/dev/null || { echo "adb not found (sudo pacman -S android-tools)" >&2; exit 1; }
if [ "$(adb get-state 2>/dev/null)" != device ]; then
  echo "No authorized ADB device. Enable Frameo Settings > About > Beta > ADB Access," >&2
  echo "turn off 'transfer from computer', and accept the prompt on the frame." >&2
  adb devices -l >&2
  exit 1
fi

SERIAL=$(adb get-serialno)
OUT=${OUT:-backups/$SERIAL}
mkdir -p "$OUT/parts"
rm -f "$OUT/parts/MISMATCHES"
HELPER=/data/local/tmp/fbackup.sh
adb push "$(dirname "$0")/backup-device.sh" "$HELPER" >/dev/null

dev() { adb exec-out "su -c 'sh $HELPER $*'" | tr -d '\r'; }

[ "$(dev uid)" = 0 ] || { echo "su did not give root" >&2; exit 1; }
HASH=$(dev hashtool)
DEVGZ=$(dev hasgzip)
echo "Serial $SERIAL -> $OUT (hash: $HASH, on-device gzip: $DEVGZ)"

if command -v pv >/dev/null; then meter() { pv -b -r -N "$1"; }; else meter() { cat; }; fi

# fetch NAME NODE [SECTORS] - copy a node to $OUT/parts/NAME.img.gz and verify it
fetch() {
  local name=$1 node=$2 count=${3:-}
  local f="$OUT/parts/$name.img.gz" devsum got
  devsum=$(dev hash "$HASH" "$node" $count | awk '{print $1}')
  if [ -s "$f" ] && [ "$(gzip -dc "$f" | $HASH | awk '{print $1}')" = "$devsum" ]; then
    echo "  $name: already backed up"
    return
  fi
  echo "  $name: reading $node${count:+ ($count sectors)}"
  if [ "$DEVGZ" = yes ]; then
    dev dump "$node" $count | base64 -d | meter "$name" > "$f.tmp"
  else
    dev dump "$node" $count | base64 -d | meter "$name" | gzip -1 > "$f.tmp"
  fi
  got=$(gzip -dc "$f.tmp" | $HASH | awk '{print $1}')
  if [ "$got" = "$devsum" ]; then
    mv "$f.tmp" "$f"
    echo "$devsum  $name.img" >> "$OUT/parts/SUMS.$HASH"
  else
    mv "$f.tmp" "$f.mismatch"
    echo "  $name: MISMATCH device=$devsum host=$got (kept as $f.mismatch)" >&2
    echo "$name" >> "$OUT/parts/MISMATCHES"
  fi
}

echo "Collecting device info..."
dev info >/dev/null
rm -rf "$OUT/info"
adb pull /data/local/tmp/fbinfo "$OUT/info" >/dev/null
[ -s "$OUT/info/live.dtb" ] && command -v dtc >/dev/null &&
  dtc -q -I dtb -O dts -o "$OUT/info/live.dts" "$OUT/info/live.dtb" || true

echo "Backing up partitions..."
# Sectors 0..16383: primary GPT plus the idbloader (DDR init + miniloader)
fetch 00-gpt-idbloader /dev/block/mmcblk2 16384
dev parts > "$OUT/parts/partitions.txt"
while read -r node name; do
  if [ "$name" = userdata ] && [ "$WITH_USERDATA" = 0 ]; then
    echo "  userdata: skipped (pass --with-userdata)"
    continue
  fi
  fetch "${node#mmcblk2}-$name" "/dev/block/$node" </dev/null
done < "$OUT/parts/partitions.txt"

dev cleanup >/dev/null
echo "Done. Checksums in $OUT/parts/SUMS.$HASH"
[ -s "$OUT/parts/MISMATCHES" ] && echo "Mismatched (likely live-mounted, re-run to retry): $(tr '\n' ' ' < "$OUT/parts/MISMATCHES")"
exit 0
