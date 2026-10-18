#!/usr/bin/env python3
"""Extract the GSL3676 touchscreen firmware from a stock FRAME156 kernel.

    scripts/extract-touch-fw.py backups/unit1/parts/p5-kernel.img.gz \
        rootfs_overlay/lib/firmware/silead/gsl3676.fw

The stock gslX680 driver is built into the Android kernel and carries a
firmware table per touch panel model. This frame uses
"Kingvina_FG1509_2_GSL3676_HuiY". Its table (FW_Kingvina_FG1509_2_GSL3676_HuiY,
4686 {u32 offset, u32 value} pairs) is already in the little-endian format
the mainline silead driver loads, so it's copied out as is.

The location was found with kallsyms (vmlinux-to-elf) in the
FrameO.DP105F.v2026010414 kernel from unit 1. Other kernel builds
put it elsewhere, which the hash check catches.
"""
import gzip
import hashlib
import sys

KERNEL_VA_BASE = 0xFFFFFF8008080000
FW_VA = 0xFFFFFF8008D386A8  # FW_Kingvina_FG1509_2_GSL3676_HuiY
FW_ENTRIES = 4686
FW_SHA256 = "20d3351a"  # prefix of the known-good extraction

src, dst = sys.argv[1], sys.argv[2]
opener = gzip.open if src.endswith(".gz") else open
with opener(src, "rb") as f:
    part = f.read()

# The kernel partition holds an arm64 Image behind an 8-byte "KRNL" header
if part[:4] != b"KRNL":
    sys.exit(f"{src}: no KRNL header")
image = part[8:]

start = FW_VA - KERNEL_VA_BASE
fw = image[start:start + 8 * FW_ENTRIES]
digest = hashlib.sha256(fw).hexdigest()
if not digest.startswith(FW_SHA256):
    sys.exit(f"unexpected firmware contents (sha256 {digest}); different kernel build?")

with open(dst, "wb") as f:
    f.write(fw)
print(f"wrote {dst}: {FW_ENTRIES} entries, sha256 {digest}")
