#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Make the stage 2 DTB for the dodge kexec chain-loader.

Usage: stage2-dtb.py <built dodge.dtb> <live.dtb> <out.dtb> [ramoops] [fb] [peripheral]

ABL fills the `memory` node at boot and kexec does not, so its reg is
taken from the phone's live FDT (/sys/firmware/fdt from a rooted
capture, kept outside git). The upstream DTS carries another phone's
map. `memory@a0000000` keeps size 0.

ramoops  add a ramoops node at OxygenOS's ramoops address and layout
         (dev-docs/2026-10-15-fastboot-boot-kexec-ramoops.md)
fb       reserve ABL's splash region and add a simple-framebuffer there
         (dev-docs/2026-10-15-fastboot-boot-kexec-fb.md)
Both were tried once and showed nothing; they are kept for retries.
peripheral  dr_mode = "peripheral" and no usb-role-switch on the dwc3
            node. The role otherwise comes from pmic_glink, which this
            initramfs does not load.
"""
import re
import subprocess
import sys


def dts(path):
    return subprocess.run(["dtc", "-q", "-I", "dtb", "-O", "dts", path],
                          capture_output=True, text=True, check=True).stdout


def node_span(s, header):
    i = s.index(header)
    depth = 0
    for k in range(i, len(s)):
        if s[k] == "{":
            depth += 1
        elif s[k] == "}":
            depth -= 1
            if depth == 0:
                return i, k
    raise ValueError(header)


def insert_in(s, header, text):
    _, j = node_span(s, header)
    line = s.rindex("\n", 0, j)
    return s[:line] + text.rstrip("\n") + s[line:]


built, live, out, *opts = sys.argv[1:]
ours, theirs = dts(built), dts(live)

i, j = node_span(theirs, "\n\tmemory {")
live_reg = re.search(r"reg = <[^>]*>;", theirs[i:j]).group(0)
i, j = node_span(ours, "\n\tmemory {")
block = ours[i:j]
ours = ours[:i] + block.replace(re.search(r"reg = <[^>]*>;", block).group(0), live_reg) + ours[j:]

if "ramoops" in opts:
    ours = insert_in(ours, "reserved-memory {", """
		ramoops@880000000 {
			compatible = "ramoops";
			reg = <0x08 0x80000000 0x00 0x240000>;
			record-size = <0x00>;
			console-size = <0x40000>;
			ftrace-size = <0x00>;
			pmsg-size = <0x200000>;
			ecc-size = <0x00>;
			no-map;
		};
""")

if "peripheral" in opts:
    if ours.count('dr_mode = "otg";') != 1 or ours.count("usb-role-switch;") != 1:
        raise SystemExit("expected exactly one otg dr_mode and one usb-role-switch")
    ours = ours.replace('dr_mode = "otg";', 'dr_mode = "peripheral";', 1)
    ours = re.sub(r"\n[ \t]*usb-role-switch;\n", "\n", ours, count=1)

if "fb" in opts:
    ours = insert_in(ours, "reserved-memory {", """
		splash@fc800000 {
			reg = <0x00 0xfc800000 0x00 0x2b00000>;
			no-map;
		};
""")
    ours = insert_in(ours, "\n\tchosen {", """
		framebuffer@fc800000 {
			compatible = "simple-framebuffer";
			reg = <0x00 0xfc800000 0x00 0x1167000>;
			width = <1440>;
			height = <3168>;
			stride = <5760>;
			format = "a8r8g8b8";
		};
""")

subprocess.run(["dtc", "-q", "-I", "dts", "-O", "dtb", "-o", out, "-"],
               input=ours, text=True, check=True)
