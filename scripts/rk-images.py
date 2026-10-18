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
    elif len(args) == 3 and args[0] == "gpt-backup":
        gpt_backup(args[1], args[2])
    elif len(args) == 4 and args[0] == "gpt-bootable":
        gpt_bootable(args[1], int(args[2]), args[3] == "on")
    else:
        sys.exit(__doc__)
