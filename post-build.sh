#!/usr/bin/env bash

set -e

# Copy the fwup includes to the images dir
cp -rf $NERVES_DEFCONFIG_DIR/fwup_include $BINARIES_DIR

# Buildroot's Panfrost needs Clang, libclc and the SPIR-V translator to
# precompile Mesa's OpenCL C shaders at build time. At runtime Mesa only
# links libLLVM, so leave the rest out of the rootfs.
rm -rf $TARGET_DIR/usr/lib/libclang*.so* \
    $TARGET_DIR/usr/lib/libLLVMSPIRVLib.so* \
    $TARGET_DIR/usr/lib/clang \
    $TARGET_DIR/usr/share/clc \
    $TARGET_DIR/usr/bin/diagtool \
    $TARGET_DIR/usr/bin/llvm-spirv

# Create the fwup ops script to handling MicroSD/eMMC operations at runtime
# NOTE: revert.fw is the previous, more limited version of this. ops.fw is
#       backwards compatible.
mkdir -p $TARGET_DIR/usr/share/fwup
NERVES_SDK_IMAGES=$BINARIES_DIR \
    $HOST_DIR/usr/bin/fwup -c -f $NERVES_DEFCONFIG_DIR/fwup-ops.conf -o $TARGET_DIR/usr/share/fwup/ops.fw
ln -sf ops.fw $TARGET_DIR/usr/share/fwup/revert.fw
