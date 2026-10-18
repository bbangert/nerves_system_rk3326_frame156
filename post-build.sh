#!/usr/bin/env bash

set -e

# Copy the fwup includes to the images dir
cp -rf $NERVES_DEFCONFIG_DIR/fwup_include $BINARIES_DIR

# Android bootloader messages that select the slot: the vendor U-Boot boots
# the "recovery" partition (slot B) while misc starts with "boot-recovery",
# and "boot" (slot A) otherwise. Both fwup.conf and fwup-ops.conf use them.
python3 -I - "$BINARIES_DIR" <<'EOF'
import os, sys
out = sys.argv[1]
open(os.path.join(out, "bcb-slot-a.bin"), "wb").write(bytes(2048))
open(os.path.join(out, "bcb-slot-b.bin"), "wb").write(b"boot-recovery".ljust(2048, b"\0"))
EOF

# Create the fwup ops script to handling MicroSD/eMMC operations at runtime
# NOTE: revert.fw is the previous, more limited version of this. ops.fw is
#       backwards compatible.
mkdir -p $TARGET_DIR/usr/share/fwup
NERVES_SDK_IMAGES=$BINARIES_DIR \
    $HOST_DIR/usr/bin/fwup -c -f $NERVES_DEFCONFIG_DIR/fwup-ops.conf -o $TARGET_DIR/usr/share/fwup/ops.fw
ln -sf ops.fw $TARGET_DIR/usr/share/fwup/revert.fw
