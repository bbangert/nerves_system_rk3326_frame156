# Distro-boot probe for the FRAME156: proves the vendor U-Boot runs this
# script, leaves a marker and a dump of its environment where loader mode
# can read them back, then enters loader mode itself.
#
# Sector 0x9000 is 2 MiB into the misc partition: below the 32 MiB that
# the vendor rockusb lets rkdeveloptool read, and clear of the Android
# bootloader message at the start of misc.

mw.l 0x0a400000 0x45424f52 0x80
mmc dev ${devnum}
mmc write 0x0a400000 0x9000 1
mw.b 0x0a500000 0 0x8000
env export -t 0x0a500000
mmc write 0x0a500000 0x9001 0x40
rockusb 0 ${devtype} ${devnum}
reset
