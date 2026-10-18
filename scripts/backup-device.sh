#!/system/bin/sh
# Runs on the frame as root (via the stock su). Driven by scripts/backup.sh.
#
# Binary data goes out as base64 because `adb exec-out "su -c ..."` turns
# LF into CRLF. Reads are always sequential from the start of a node because
# 32-bit dd can't seek past 2 GiB on mmcblk2.

cmd=$1
shift

# src NODE [SECTORS] - stream a block node, optionally only its first SECTORS
src() {
  if [ -n "$2" ]; then
    dd if="$1" bs=512 count="$2" 2>/dev/null
  else
    cat "$1"
  fi
}

case "$cmd" in
  uid)
    id -u
    ;;
  hashtool)
    for h in sha256sum sha1sum md5sum; do
      if command -v $h >/dev/null 2>&1; then echo $h; exit 0; fi
    done
    exit 1
    ;;
  hasgzip)
    if command -v gzip >/dev/null 2>&1; then echo yes; else echo no; fi
    ;;
  parts)
    for p in /sys/class/block/mmcblk2p*; do
      echo "${p##*/} $(grep '^PARTNAME=' $p/uevent | cut -d= -f2)"
    done
    for b in mmcblk2boot0 mmcblk2boot1; do
      [ -e /dev/block/$b ] && echo "$b $b"
    done
    ;;
  hash)
    tool=$1
    shift
    src "$@" | $tool
    ;;
  dump)
    if command -v gzip >/dev/null 2>&1; then
      src "$@" | gzip -1 | base64
    else
      src "$@" | base64
    fi
    ;;
  info)
    d=/data/local/tmp/fbinfo
    rm -rf $d
    mkdir -p $d
    cd $d || exit 1
    getprop > getprop.txt
    for f in cmdline cpuinfo meminfo partitions version interrupts iomem modules; do
      cat /proc/$f > proc-$f.txt 2>&1
    done
    mount > mount.txt 2>&1
    dmesg > dmesg.txt 2>&1
    lsmod > lsmod.txt 2>&1
    ls -l /dev/block/platform/*/by-name/ /dev/block/by-name/ > by-name.txt 2>&1
    ls -lR /vendor/etc/firmware /system/etc/firmware /vendor/lib/modules \
      /system/lib/modules > firmware-modules.txt 2>&1
    # Live device tree and kernel config: the starting point for the Nerves port
    cp /sys/firmware/fdt live.dtb 2>/dev/null
    cp /proc/config.gz kernel-config.gz 2>/dev/null
    for f in /sys/kernel/debug/gpio /sys/kernel/debug/clk/clk_summary \
      /sys/kernel/debug/regulator/regulator_summary \
      /sys/kernel/debug/pinctrl/*/pinmux-pins; do
      [ -e "$f" ] || continue
      n=$(echo "${f#/sys/kernel/debug/}" | tr / _)
      cat "$f" > debug-$n.txt 2>&1
    done
    grep -H . /sys/bus/sdio/devices/*/uevent > sdio.txt 2>&1
    grep -H . /sys/bus/i2c/devices/*/name > i2c.txt 2>&1
    grep -H . /sys/bus/usb/devices/*/uevent > usb.txt 2>&1
    for drv in /sys/bus/*/drivers/*; do
      echo "== $drv"
      ls "$drv"
    done > drivers.txt 2>&1
    chmod -R 755 $d
    ;;
  cleanup)
    rm -rf /data/local/tmp/fbinfo
    rm -f "$0"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
