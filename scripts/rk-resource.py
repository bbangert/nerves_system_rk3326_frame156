#!/usr/bin/env python3
"""Pack and unpack Rockchip resource images (the "RSCE" format).

The vendor U-Boot reads the kernel device tree (rk-kernel.dtb) and boot
logos from these, either from the `resource` partition or from the
"second" stage of an Android boot image.

usage:
  rk-resource.py unpack <resource.img> <outdir>
  rk-resource.py pack <resource.img> <file>...   (stored under their basenames)
"""
import os
import struct
import sys

BLOCK = 512
# magic, partition version, index table version, header size (blocks),
# table offset (blocks), table entry size (blocks), entry count
HEADER = struct.Struct("<4sHHBBBxI")
ENTRY_NAME_LEN = 256


def unpack(image, outdir):
    data = open(image, "rb").read()
    magic, _, _, _, tbl_off, entry_size, count = HEADER.unpack_from(data)
    if magic != b"RSCE":
        sys.exit("%s: not a Rockchip resource image" % image)
    os.makedirs(outdir, exist_ok=True)
    for i in range(count):
        entry = data[(tbl_off + i * entry_size) * BLOCK:][:entry_size * BLOCK]
        if entry[:4] != b"ENTR":
            sys.exit("entry %d: bad magic" % i)
        name = entry[4:4 + ENTRY_NAME_LEN].split(b"\0")[0].decode()
        offset, size = struct.unpack_from("<II", entry, 4 + ENTRY_NAME_LEN)
        content = data[offset * BLOCK:offset * BLOCK + size]
        open(os.path.join(outdir, name), "wb").write(content)
        print("%s (%d bytes)" % (name, size))


def pack(image, files):
    header_blocks = 1
    entry_blocks = 1
    table = b""
    contents = b""
    next_block = header_blocks + entry_blocks * len(files)
    for path in files:
        content = open(path, "rb").read()
        name = os.path.basename(path).encode()
        if len(name) >= ENTRY_NAME_LEN:
            sys.exit("%s: name too long" % path)
        entry = b"ENTR" + name.ljust(ENTRY_NAME_LEN, b"\0")
        entry += struct.pack("<II", next_block, len(content))
        table += entry.ljust(entry_blocks * BLOCK, b"\0")
        padded = content.ljust(-(-len(content) // BLOCK) * BLOCK, b"\0")
        contents += padded
        next_block += len(padded) // BLOCK
    header = HEADER.pack(b"RSCE", 0, 0, header_blocks, header_blocks,
                         entry_blocks, len(files))
    with open(image, "wb") as f:
        f.write(header.ljust(header_blocks * BLOCK, b"\0") + table + contents)


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "unpack":
        unpack(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 4 and sys.argv[1] == "pack":
        pack(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
