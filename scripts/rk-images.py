#!/usr/bin/env python3
"""Small image helpers for bring-up, so the host needs no U-Boot tools.

usage:
  rk-images.py script <boot.cmd> <boot.scr>
      Wrap a U-Boot script in a legacy image (like mkimage -T script).
  rk-images.py ramdisk <initramfs.cpio.gz> <uInitrd>
      Wrap an initramfs in a legacy arm64 ramdisk image.
  rk-images.py gpt-bootable <gpt.bin> <partition number> <on|off>
      Set or clear the legacy BIOS bootable attribute (bit 2) of a partition
      in a GPT dump. The dump is either the primary GPT (sector 0 onward,
      protective MBR included) or the backup (entries followed by the
      header in the last sector). CRCs are updated.
  rk-images.py bootimg <Image> <cmdline> <out.img> [ramdisk] [second]
      Build an Android boot image (header v0) for the vendor U-Boot's
      boot_android. Without a ramdisk, an empty initramfs is used. Without
      a second stage (Rockchip resource image), U-Boot uses the device tree
      in the unit's own resource partition.
  rk-images.py gpt-rename <gpt.bin> <partition number> <name>
      Rename a partition in a primary or backup GPT dump; CRCs are updated.
  rk-images.py gpt-backup <primary.bin> <backup.bin>
      Build the backup GPT (entry array, then header) that belongs at the
      end of the disk, from a primary GPT dump (sector 0 onward). Write it
      at the sector the primary header names as its alternate, minus the
      entry array size.
"""
import struct
import sys
import time
import zlib

SECTOR = 512
IH_MAGIC = 0x27051956
IH_OS_LINUX = 5
IH_ARCH_ARM64 = 22
IH_TYPE_RAMDISK = 3
IH_TYPE_SCRIPT = 6
IH_COMP_NONE = 0


def legacy_image(data, image_type, name):
    header = struct.pack(">IIIIIIIBBBB32s", IH_MAGIC, 0, int(time.time()),
                         len(data), 0, 0, zlib.crc32(data), IH_OS_LINUX,
                         IH_ARCH_ARM64, image_type, IH_COMP_NONE,
                         name.encode()[:31])
    hcrc = zlib.crc32(header)
    return header[:4] + struct.pack(">I", hcrc) + header[8:] + data


def script(src, dst):
    body = open(src, "rb").read()
    # Script images are multi-file images: a size table, then the data
    data = struct.pack(">II", len(body), 0) + body
    open(dst, "wb").write(legacy_image(data, IH_TYPE_SCRIPT, "boot script"))


def ramdisk(src, dst):
    data = open(src, "rb").read()
    open(dst, "wb").write(legacy_image(data, IH_TYPE_RAMDISK, "initramfs"))


def gpt_bootable(path, number, on):
    buf = bytearray(open(path, "rb").read())
    # Primary dumps start with the protective MBR; backup dumps end with
    # the header.
    if buf[SECTOR:SECTOR + 8] == b"EFI PART":
        hdr_off = SECTOR
    elif buf[-SECTOR:-SECTOR + 8] == b"EFI PART":
        hdr_off = len(buf) - SECTOR
    else:
        sys.exit("%s: no GPT header found" % path)
    hdr_size, = struct.unpack_from("<I", buf, hdr_off + 12)
    my_lba, = struct.unpack_from("<Q", buf, hdr_off + 24)
    entries_lba, = struct.unpack_from("<Q", buf, hdr_off + 72)
    count, entry_size = struct.unpack_from("<II", buf, hdr_off + 80)
    # Entry array location relative to the dump
    entries_off = hdr_off + (entries_lba - my_lba) * SECTOR
    attr_off = entries_off + (number - 1) * entry_size + 48
    attr, = struct.unpack_from("<Q", buf, attr_off)
    attr = attr | 4 if on else attr & ~4
    struct.pack_into("<Q", buf, attr_off, attr)
    entries = bytes(buf[entries_off:entries_off + count * entry_size])
    struct.pack_into("<I", buf, hdr_off + 88, zlib.crc32(entries))
    struct.pack_into("<I", buf, hdr_off + 16, 0)
    struct.pack_into("<I", buf, hdr_off + 16,
                     zlib.crc32(bytes(buf[hdr_off:hdr_off + hdr_size])))
    open(path, "wb").write(buf)
    name = buf[attr_off - 48 + 56:attr_off - 48 + 128].decode("utf-16le").rstrip("\0")
    print("partition %d (%s): attributes now %#x" % (number, name, attr))


def empty_initramfs():
    """A gzipped newc cpio holding only the trailer: with no /init in it,
    the kernel mounts root= as usual."""
    import gzip
    name = b"TRAILER!!!\0"
    hdr = b"070701" + b"".join(b"%08X" % v for v in (
        0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, len(name), 0))
    entry = hdr + name
    entry += b"\0" * (-len(entry) % 4)
    entry += b"\0" * (-len(entry) % 512)
    return gzip.compress(entry, mtime=0)


def bootimg(kernel_path, cmdline, dst, ramdisk_path=None, second_path=None):
    """Android boot image, header v0, with the stock recovery image's
    layout (2 KiB pages, base 0x10000000)."""
    import hashlib
    page = 2048
    base = 0x10000000
    kernel = open(kernel_path, "rb").read()
    ramdisk = open(ramdisk_path, "rb").read() if ramdisk_path else empty_initramfs()
    second = open(second_path, "rb").read() if second_path else b""
    cmd = cmdline.encode()
    if len(cmd) >= 512:
        sys.exit("command line too long for the v0 header")
    sha = hashlib.sha1()
    for blob in (kernel, ramdisk, second):
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))
    hdr = struct.pack("<8s10I16s512s32s1024s", b"ANDROID!",
                      len(kernel), base + 0x00008000,
                      len(ramdisk), base + 0x01000000,
                      len(second), base + 0x00f00000 if second else 0,
                      base + 0x00000100, page, 0, 0,
                      b"", cmd, sha.digest(), b"")
    pad = lambda b: b + b"\0" * (-len(b) % page)
    with open(dst, "wb") as f:
        f.write(pad(hdr) + pad(kernel) + pad(ramdisk) + (pad(second) if second else b""))


def gpt_rename(path, number, name):
    buf = bytearray(open(path, "rb").read())
    if buf[SECTOR:SECTOR + 8] == b"EFI PART":
        hdr_off = SECTOR
    elif buf[-SECTOR:-SECTOR + 8] == b"EFI PART":
        hdr_off = len(buf) - SECTOR
    else:
        sys.exit("%s: no GPT header found" % path)
    hdr_size, = struct.unpack_from("<I", buf, hdr_off + 12)
    my_lba, = struct.unpack_from("<Q", buf, hdr_off + 24)
    entries_lba, = struct.unpack_from("<Q", buf, hdr_off + 72)
    count, entry_size = struct.unpack_from("<II", buf, hdr_off + 80)
    entries_off = hdr_off + (entries_lba - my_lba) * SECTOR
    name_off = entries_off + (number - 1) * entry_size + 56
    encoded = name.encode("utf-16le")
    if len(encoded) > 72:
        sys.exit("name too long")
    buf[name_off:name_off + 72] = encoded.ljust(72, b"\0")
    entries = bytes(buf[entries_off:entries_off + count * entry_size])
    struct.pack_into("<I", buf, hdr_off + 88, zlib.crc32(entries))
    struct.pack_into("<I", buf, hdr_off + 16, 0)
    struct.pack_into("<I", buf, hdr_off + 16,
                     zlib.crc32(bytes(buf[hdr_off:hdr_off + hdr_size])))
    open(path, "wb").write(buf)
    print("partition %d renamed to %s" % (number, name))


def gpt_backup(src, dst):
    buf = open(src, "rb").read()
    hdr = bytearray(buf[SECTOR:2 * SECTOR])
    if hdr[:8] != b"EFI PART":
        sys.exit("%s: no primary GPT header at sector 1" % src)
    hdr_size, = struct.unpack_from("<I", hdr, 12)
    my_lba, alt_lba = struct.unpack_from("<QQ", hdr, 24)
    entries_lba, = struct.unpack_from("<Q", hdr, 72)
    count, entry_size = struct.unpack_from("<II", hdr, 80)
    entries_bytes = count * entry_size
    entries_sectors = -(-entries_bytes // SECTOR)
    entries = buf[entries_lba * SECTOR:entries_lba * SECTOR + entries_bytes]
    backup_entries_lba = alt_lba - entries_sectors
    struct.pack_into("<QQ", hdr, 24, alt_lba, my_lba)
    struct.pack_into("<Q", hdr, 72, backup_entries_lba)
    struct.pack_into("<I", hdr, 16, 0)
    struct.pack_into("<I", hdr, 16, zlib.crc32(bytes(hdr[:hdr_size])))
    out = entries.ljust(entries_sectors * SECTOR, b"\0") + bytes(hdr)
    open(dst, "wb").write(out)
    print("backup GPT: %d sectors, write at sector %d (header at %d)" % (
        len(out) // SECTOR, backup_entries_lba, alt_lba))


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "script":
        script(args[1], args[2])
    elif len(args) == 3 and args[0] == "ramdisk":
        ramdisk(args[1], args[2])
    elif len(args) in (4, 5, 6) and args[0] == "bootimg":
        bootimg(args[1], args[2], args[3], *(a or None for a in args[4:]))
    elif len(args) == 4 and args[0] == "gpt-rename":
        gpt_rename(args[1], int(args[2]), args[3])
    elif len(args) == 3 and args[0] == "gpt-backup":
        gpt_backup(args[1], args[2])
    elif len(args) == 4 and args[0] == "gpt-bootable":
        gpt_bootable(args[1], int(args[2]), args[3] == "on")
    else:
        sys.exit(__doc__)
