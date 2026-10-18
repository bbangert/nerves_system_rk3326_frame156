#!/usr/bin/env python3
"""Rewrite phandle numbers in a decompiled DTS as &labels.

The stock DTB keeps __symbols__, so each phandle can be mapped back to the
label the vendor used. Only the first cell of each <...> group and cells
following a GPIO/clock-style specifier are candidates, which is a heuristic:
check anything surprising against the raw live.dts.

usage: annotate-dts.py live.dts > live-annotated.dts
"""
import re
import sys

src = open(sys.argv[1]).read()

# path -> label from __symbols__
symbols = {}
m = re.search(r"__symbols__ \{(.*?)\n\t\};", src, re.S)
for label, path in re.findall(r'\t\t(\S+) = "([^"]+)";', m.group(1)):
    symbols.setdefault(path, label)

# Walk nodes to learn each phandle's path
phandles = {}
stack = []
for line in src.splitlines():
    s = line.strip()
    if s.endswith("{"):
        name = s[:-1].strip().split(":")[-1].strip()
        stack.append(name)
    elif s.startswith("};"):
        stack.pop()
    else:
        pm = re.match(r"phandle = <(0x[0-9a-f]+)>;", s)
        if pm:
            path = "/" + "/".join(stack[1:])
            phandles[int(pm.group(1), 16)] = symbols.get(path, path)

# Properties whose cells are (phandle, args...) lists we can't parse without
# #cells; only rewrite the first cell of each, plus single-phandle props.
def fix(match):
    prop, cells = match.group(1), match.group(2)
    parts = cells.split()
    if not parts or prop in ("reg", "phandle", "interrupts", "linux,phandle"):
        return match.group(0)
    if prop.endswith(("-gpios", "-gpio", "gpios", "gpio")) or prop in (
        "pwms", "io-channels", "pinctrl-0", "pinctrl-1", "pinctrl-2",
        "remote-endpoint", "backlight", "power-supply", "memory-region",
        "logo-memory-region", "phys", "iommus", "rockchip,grf",
        "interrupt-parent", "clocks", "resets", "power-domains",
        "vcc-supply", "vmmc-supply", "vqmmc-supply", "mmc-pwrseq",
        "connect", "rockchip,pmu", "assigned-clocks", "assigned-clock-parents",
    ) or prop.endswith("-supply"):
        v = int(parts[0], 16) if parts[0].startswith("0x") else None
        if v in phandles:
            parts[0] = "&" + phandles[v].lstrip("/")
    return "%s = <%s>;" % (prop, " ".join(parts))

out = re.sub(r"([\w,#.\-]+) = <([^>]*)>;", fix, src)
sys.stdout.write(out)
