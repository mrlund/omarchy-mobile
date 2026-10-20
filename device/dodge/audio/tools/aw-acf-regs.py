#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""List the sections of an Awinic ACF (aw882xx_acf.bin) and write one
profile's register table per amplifier as aw882308-<addr>.bin: little-endian
u16 (reg, value) pairs, the format device/dodge/audio/aw882308 loads.

Layout per the GPL-2.0 aw882xx driver (aw882xx_data_type.h). The ACF itself
comes from the phone's own odm partition; neither it nor the output belongs
in git.

usage: aw-acf-regs.py ACF [--profile Music] [--chip 0x2308] [--out DIR]
"""
import argparse, os, struct, sys

HDR = struct.Struct("<I24s16s4sIIIII12x")           # aw_cfg_hdr, 80 bytes
DDE0 = struct.Struct("<I16sHHHHIIII20x")            # aw_cfg_dde
DDE1 = struct.Struct("<I16sHHHHIIII32sI16x")        # aw_cfg_dde_v_1_0_0_0
SEC = {0: "reg", 1: "dsp", 2: "dsp_cfg", 3: "dsp_fw", 4: "hdr_reg",
       5: "hdr_dsp_cfg", 6: "hdr_dsp_fw", 7: "multibin", 8: "skt_project",
       9: "dsp_project", 10: "monitor"}
TYPE = {0: "dev", 1: "skt", 2: "dev_default"}

def cstr(b):
    return b.split(b"\0", 1)[0].decode(errors="replace")

def regs_raw(blob):
    return [struct.unpack_from("<HH", blob, i) for i in range(0, len(blob) - 3, 4)]

def regs_hdr(blob):
    # 60-byte bin header (aw882xx_bin_parse.c): check_sum, header_ver,
    # data_type, data_ver, data_len, ui_ver, chip_type[8], reg_byte_len,
    # data_byte_len, device_addr, ...; register data follows.
    (_cs, _hv, dtype, _dv, dlen, _ui, _ct, rbl, dbl, _addr) = \
        struct.unpack_from("<6I8s3I", blob, 0)
    if dtype != 0:
        raise ValueError("hdr section is not registers (type %#x)" % dtype)
    data = blob[60:60 + dlen]
    step = rbl + dbl
    out = []
    for i in range(0, len(data) - step + 1, step):
        reg = int.from_bytes(data[i:i + rbl], "little")
        val = int.from_bytes(data[i + rbl:i + step], "little")
        out.append((reg, val))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("acf")
    ap.add_argument("--profile")
    ap.add_argument("--chip", type=lambda s: int(s, 0), default=0x2308)
    ap.add_argument("--out")
    a = ap.parse_args()
    d = open(a.acf, "rb").read()
    (aid, proj, cust, ver, _auth, ddt_size, ddt_num, off, hver) = HDR.unpack_from(d, 0)
    print("id %#x project %s custom %s ddt %d x %d at %#x hdr_version %#x" %
          (aid, cstr(proj), cstr(cust), ddt_num, ddt_size, off, hver))
    # hdr_version 1 (0.0.0.1): a_ddt_size is the whole table, 64-byte
    # entries; 0x01000000: 96-byte entries with profile name and chip id.
    v1 = hver == 0x01000000
    ddt_size = DDE1.size if v1 else DDE0.size
    picked = {}
    for i in range(ddt_num):
        o = off + i * ddt_size
        if v1:
            (t, name, idx, bus, addr, prof, dt, size, doff, _crc, pstr, chip) = DDE1.unpack_from(d, o)
            pstr = cstr(pstr)
        else:
            (t, name, idx, bus, addr, prof, dt, size, doff, _crc) = DDE0.unpack_from(d, o)
            pstr, chip = str(prof), None
        print("  %-11s %-8s idx %d bus %d addr %#04x prof %-10s chip %s size %d" %
              (TYPE.get(t, t), SEC.get(dt, dt), idx, bus, addr, pstr,
               "%#06x" % chip if chip is not None else "-", size))
        if dt not in (0, 4) or (chip is not None and chip != a.chip):
            continue
        blob = d[doff:doff + size]
        regs = regs_raw(blob) if dt == 0 else regs_hdr(blob)
        if a.profile and pstr == a.profile:
            picked[(t, idx, addr)] = regs
        if not a.out:
            for r, v in regs:
                print("      %#04x = %#06x" % (r, v))
    if a.out:
        if not picked:
            sys.exit("profile %r not found" % a.profile)
        os.makedirs(a.out, exist_ok=True)
        for (t, idx, addr), regs in picked.items():
            # "dev" entries carry the I2C address; "dev_default" ones only an
            # index: stock maps index 0 to 0x34 (left), 1 to 0x35 (right).
            a7 = addr if t == 0 else 0x34 + idx
            fn = os.path.join(a.out, "aw882308-%02x.bin" % a7)
            with open(fn, "wb") as f:
                for r, v in regs:
                    f.write(struct.pack("<HH", r, v))
            print("wrote %s (%d registers)" % (fn, len(regs)))

if __name__ == "__main__":
    main()
