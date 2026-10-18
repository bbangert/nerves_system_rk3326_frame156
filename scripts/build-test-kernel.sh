#!/usr/bin/env bash
# Build a bring-up kernel and a tiny busybox initramfs, packed as an
# Android boot image for the frame's *recovery* partition.
#
# The stock vendor U-Boot boots the recovery partition when Android reboots
# with "recovery" (adb reboot recovery). It takes the kernel, ramdisk and
# device tree (rk-kernel.dtb in the Rockchip resource image in the "second"
# slot) from that partition, so this tests our kernel and device tree with
# Android left intact. A cold power cycle goes back to normal Android.
#
# This duplicates what the Buildroot build does for the kernel, but
# rebuilds in minutes, which is what bring-up needs.
#
#   scripts/build-test-kernel.sh
#
# Output: .build/test/recovery.img (plus Image, the dtb and the initramfs)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$REPO/.build
DL=$BUILD/dl
OUT=$BUILD/test
STOCK_RESOURCE=${STOCK_RESOURCE:-}

LINUX_VERSION=7.1.2
BUSYBOX_VERSION=1.37.0
TOOLCHAIN_VERSION=15.3.0-8DAF9F3
TOOLCHAIN=nerves_toolchain_aarch64_nerves_linux_gnu-linux_$(uname -m)-$TOOLCHAIN_VERSION
TOOLCHAIN_URL=https://github.com/nerves-project/toolchains/releases/download/v${TOOLCHAIN_VERSION%%-*}/$TOOLCHAIN.tar.xz
JOBS=$(nproc)

# Bring-up command line. rk_early_wdt turns a hang into a warm reset (the
# vendor U-Boot never starts the watchdog) and initcall_debug shows in the
# ramoops log where a hang happened. Recovery boots are one-shot, so after
# a reset or a power cycle the frame comes back up in Android, which can
# read the log from /sys/fs/pstore.
CMDLINE=${CMDLINE:-"console=tty1 console=ttyGS0,115200 consoleblank=0 loglevel=8 ignore_loglevel initcall_debug rk_early_wdt clk_ignore_unused panic=5 softlockup_panic=1"}

mkdir -p "$DL" "$OUT"

# The stock resource partition image (from the backup), for its device
# tree and logos
[ -f "$STOCK_RESOURCE" ] || {
  echo "Set STOCK_RESOURCE to the stock resource partition image" >&2
  exit 1
}

for tool in bc flex bison mkbootimg cpio; do
  command -v $tool >/dev/null || { echo "Missing host tool: $tool" >&2; exit 1; }
done

fetch() { # url file
  if [ ! -s "$DL/$2" ]; then
    curl -fL --retry 3 -o "$DL/$2.tmp" "$1"
    mv "$DL/$2.tmp" "$DL/$2"
  fi
}

# Toolchain
if [ ! -x "$BUILD/$TOOLCHAIN/bin/aarch64-nerves-linux-gnu-gcc" ]; then
  fetch "$TOOLCHAIN_URL" "$TOOLCHAIN.tar.xz"
  rm -rf "$BUILD/$TOOLCHAIN"
  mkdir -p "$BUILD/$TOOLCHAIN"
  tar -xJf "$DL/$TOOLCHAIN.tar.xz" -C "$BUILD/$TOOLCHAIN" --strip-components=1
fi
CROSS=$BUILD/$TOOLCHAIN/bin/aarch64-nerves-linux-gnu-

# Kernel source, checked against kernel.org's signed checksum list
LINUX_TAR=linux-$LINUX_VERSION.tar.xz
fetch "https://cdn.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/$LINUX_TAR" "$LINUX_TAR"
fetch "https://cdn.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/sha256sums.asc" "linux-sha256sums-$LINUX_VERSION.asc"
(cd "$DL" && grep " $LINUX_TAR\$" "linux-sha256sums-$LINUX_VERSION.asc" | sha256sum -c --quiet)

LINUX=$BUILD/linux-$LINUX_VERSION
if [ ! -f "$LINUX/.patched" ]; then
  rm -rf "$LINUX"
  tar -xJf "$DL/$LINUX_TAR" -C "$BUILD"
  for p in "$REPO"/patches/linux/*.patch; do
    echo "Applying $(basename "$p")"
    patch -d "$LINUX" -p1 -s < "$p"
  done
  touch "$LINUX/.patched"
fi

# Config: the system's base config and Nerves fragment
KMAKE=(make -C "$LINUX" ARCH=arm64 CROSS_COMPILE="$CROSS" -j"$JOBS")
cp "$REPO/linux/linux-7.1.config" "$LINUX/.config"
"$LINUX/scripts/kconfig/merge_config.sh" -m -O "$LINUX" "$LINUX/.config" "$REPO/linux/nerves.fragment" >/dev/null
"${KMAKE[@]}" olddefconfig >/dev/null

cp "$REPO/dts/rk3326-pastigio-frame156.dts" "$LINUX/arch/arm64/boot/dts/"
"${KMAKE[@]}" rk3326-pastigio-frame156.dtb

# The vendor U-Boot parses the device tree in the boot image's resource
# for its own drivers and can't cope with ours, so it gets the stock one
# (below), and the test kernel carries ours (patch 0006).
DTB=$LINUX/arch/arm64/boot/dts/rk3326-pastigio-frame156.dtb
"$LINUX/scripts/config" --file "$LINUX/.config" \
  --enable ARM64_BUILTIN_DTB_OVERRIDE --set-str ARM64_BUILTIN_DTB_PATH "$DTB"
"${KMAKE[@]}" olddefconfig >/dev/null
# .incbin isn't dependency-tracked, so always relink the blob
rm -f "$LINUX/arch/arm64/kernel/builtin_dtb.o"
"${KMAKE[@]}" Image
cp "$LINUX/arch/arm64/boot/Image" "$OUT/Image"
cp "$LINUX/arch/arm64/boot/dts/rk3326-pastigio-frame156.dtb" "$OUT/"

# Static busybox for the initramfs
BUSYBOX_TAR=busybox-$BUSYBOX_VERSION.tar.bz2
fetch "https://busybox.net/downloads/$BUSYBOX_TAR" "$BUSYBOX_TAR"
fetch "https://busybox.net/downloads/$BUSYBOX_TAR.sha256" "$BUSYBOX_TAR.sha256"
(cd "$DL" && sha256sum -c --quiet "$BUSYBOX_TAR.sha256")
BUSYBOX=$BUILD/busybox-$BUSYBOX_VERSION
if [ ! -x "$BUSYBOX/busybox" ]; then
  rm -rf "$BUSYBOX"
  tar -xjf "$DL/$BUSYBOX_TAR" -C "$BUILD"
  BBMAKE=(make -C "$BUSYBOX" ARCH=arm64 CROSS_COMPILE="$CROSS" -j"$JOBS")
  "${BBMAKE[@]}" defconfig >/dev/null
  sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
    -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
    -e 's/^CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' \
    -e 's/^CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' \
    -e 's/^# CONFIG_NC_SERVER is not set/CONFIG_NC_SERVER=y/' \
    -e 's/^# CONFIG_NC_EXTRA is not set/CONFIG_NC_EXTRA=y/' "$BUSYBOX/.config"
  { yes "" || true; } | "${BBMAKE[@]}" oldconfig >/dev/null
  "${BBMAKE[@]}" busybox
fi
[ -f "$BUSYBOX/busybox.links" ] || make -C "$BUSYBOX" ARCH=arm64 CROSS_COMPILE="$CROSS" busybox.links

# Initramfs
RAMDISK=$OUT/initramfs
rm -rf "$RAMDISK"
mkdir -p "$RAMDISK"/{bin,sbin,etc,proc,sys,dev,tmp,root,usr/bin,usr/sbin,var/lib/misc}
cp "$BUSYBOX/busybox" "$RAMDISK/bin/"
while read -r app; do
  [ "$app" = /bin/busybox ] || ln -sf /bin/busybox "$RAMDISK$app"
done < "$BUSYBOX/busybox.links"
cp "$REPO/scripts/test-initramfs/init" "$RAMDISK/init"
cp "$REPO/scripts/test-initramfs/udhcpd.conf" "$RAMDISK/etc/"
chmod +x "$RAMDISK/init"
(cd "$RAMDISK" && find . | LC_ALL=C sort | cpio -o -H newc --quiet --owner=0:0) | gzip -9 > "$OUT/initramfs.cpio.gz"

# Rockchip resource image for U-Boot: the *stock* device tree and logos,
# so U-Boot behaves exactly as it does for Android
rm -rf "$OUT/resource"
python3 -I "$REPO/scripts/rk-resource.py" unpack "$STOCK_RESOURCE" "$OUT/resource" >/dev/null
RESOURCE_FILES=("$OUT/resource/rk-kernel.dtb")
for logo in logo.bmp logo_pcba.bmp; do
  [ -f "$OUT/resource/$logo" ] && RESOURCE_FILES+=("$OUT/resource/$logo")
done
python3 -I "$REPO/scripts/rk-resource.py" pack "$OUT/resource.img" "${RESOURCE_FILES[@]}"

# Same layout and load addresses as the stock recovery image
mkbootimg --header_version 0 --pagesize 2048 --base 0x10000000 \
  --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --second_offset 0x00f00000 --tags_offset 0x00000100 \
  --kernel "$OUT/Image" --ramdisk "$OUT/initramfs.cpio.gz" \
  --second "$OUT/resource.img" \
  --cmdline "$CMDLINE" \
  -o "$OUT/recovery.img"

ls -l "$OUT/recovery.img"
max=$((143360 * 512))
size=$(stat -c %s "$OUT/recovery.img")
if [ "$size" -gt "$max" ]; then
  echo "recovery.img is $size bytes; the recovery partition holds $max" >&2
  exit 1
fi
