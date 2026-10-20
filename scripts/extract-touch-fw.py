#!/usr/bin/env python3
"""Extract the GSL3676 touchscreen firmware from a stock FRAME156 kernel.

    scripts/extract-touch-fw.py backups/<serial>/parts/p5-kernel.img.gz \\
        rootfs_overlay/lib/firmware/silead/gsl3676.fw
    scripts/extract-touch-fw.py --list backups/<serial>/parts/p5-kernel.img.gz

The input is a partition from scripts/backup.sh, gzipped or not: the stock
kernel (p5-kernel, a "KRNL" image), or the stock boot or recovery partition
(p6-boot, p7-recovery: Android boot images with the same kernel). A bare
arm64 Image works too.

The stock gslX680 driver is built into the kernel and keeps a table of
panel configs, 96-byte records of {char name[64]; u64 fw; u32 entries;
u32 pad; u64 data_id; u32 data_size; u32 pad}. The stock device tree picks
one by name (gsl_name; dmesg prints "gsl_name=..."). This frame's is
Kingvina_FG1509_2_GSL3676_HuiY. Its firmware is {u32 offset, u32 value}
pairs, already the little-endian format the mainline silead driver loads,
so it's copied out as is.

The record is found by name, so any stock kernel build works. The HuiY
firmware is the same in the January and April 2026 builds (both units);
its hash is checked. Other panels (--panel) aren't checked: none of them
work on this frame's panel, and the system's device tree is only set up
for this one.
"""
import argparse
import gzip
import hashlib
import os
import struct
import sys

PANEL = "Kingvina_FG1509_2_GSL3676_HuiY"
PANEL_SHA256 = "20d3351a49725d0a3589630642252401054d5627b4a063f8041d9eb7c5ace9c7"
# The stock 4.4 kernel's link address (VA_BITS=39) is this plus the Image
# header's text_offset.
KIMAGE_VADDR = 0xFFFFFF8008000000
RECORD_NAME = 64


def load_image(path):
    """Return the arm64 Image inside a kernel, boot or recovery partition."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if data[:4] == b"KRNL":
        image = data[8:]
    elif data[:8] == b"ANDROID!":
        kernel_size, = struct.unpack_from("<I", data, 8)
        page_size, = struct.unpack_from("<I", data, 36)
        image = data[page_size:page_size + kernel_size]
    else:
        image = data
    if image[56:60] != b"ARMd":
        sys.exit(f"{path}: no arm64 kernel Image found (expected a KRNL, "
                 "Android boot image or bare Image)")
    return image


def panels(image):
    """Yield (name, record offset, fw offset, entries) for each panel config."""
    text_offset, = struct.unpack_from("<Q", image, 8)
    base = KIMAGE_VADDR + text_offset
    seen = set()
    pos = image.find(b"_GSL")
    while pos != -1:
        start = image.rfind(b"\0", max(0, pos - RECORD_NAME), pos) + 1
        if start not in seen and start + RECORD_NAME + 16 <= len(image):
            seen.add(start)
            raw = image[start:start + RECORD_NAME]
            name, _, pad = raw.partition(b"\0")
            fw, entries = struct.unpack_from("<QI", image, start + RECORD_NAME)
            off = fw - base
            if (name.isascii() and not pad.strip(b"\0")
                    and 0 < off and off + 8 * entries <= len(image)
                    and 0 < entries < 100_000
                    and looks_like_firmware(image[off:off + 8 * entries])):
                yield name.decode(), start, off, entries
        pos = image.find(b"_GSL", pos + 1)


def looks_like_firmware(fw):
    """Silead firmware writes registers 0x00-0xfc, a word at a time."""
    regs = struct.unpack_from(f"<{len(fw) // 8}Q", fw)
    return all((r & 0xFFFFFFFF) < 0x100 and r % 4 == 0 for r in regs)


def main():
    ap = argparse.ArgumentParser(
        description="Extract the GSL3676 touch firmware from a stock FRAME156 kernel.")
    ap.add_argument("src", help="p5-kernel, p6-boot or p7-recovery image from a backup")
    ap.add_argument("dst", nargs="?", help="where to write the firmware (gsl3676.fw)")
    ap.add_argument("--panel", default=PANEL,
                    help=f"panel config to extract (default {PANEL})")
    ap.add_argument("--list", action="store_true", help="list the panel configs and exit")
    args = ap.parse_args()

    image = load_image(args.src)
    found = {name: (off, entries) for name, _, off, entries in panels(image)}
    if not found:
        sys.exit(f"{args.src}: no gslX680 panel configs found in this kernel")

    if args.list:
        for name, (off, entries) in found.items():
            digest = hashlib.sha256(image[off:off + 8 * entries]).hexdigest()
            print(f"{name}  {entries} entries  sha256 {digest[:16]}")
        return
    if not args.dst:
        ap.error("dst is required unless --list is given")

    if args.panel not in found:
        sys.exit(f"{args.src}: no panel config named {args.panel}. This kernel has:\n  "
                 + "\n  ".join(found))
    off, entries = found[args.panel]
    fw = image[off:off + 8 * entries]
    digest = hashlib.sha256(fw).hexdigest()
    if args.panel == PANEL and digest != PANEL_SHA256:
        sys.exit(f"{args.panel} firmware has sha256 {digest}, expected {PANEL_SHA256}. "
                 "Not written: this kernel's copy differs from the tested one.")

    os.makedirs(os.path.dirname(os.path.abspath(args.dst)), exist_ok=True)
    with open(args.dst, "wb") as f:
        f.write(fw)
    note = "matches the tested firmware" if args.panel == PANEL else "not checked"
    print(f"wrote {args.dst}: {args.panel}, {entries} entries, sha256 {digest} ({note})")


if __name__ == "__main__":
    main()
