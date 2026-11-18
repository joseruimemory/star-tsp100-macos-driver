#!/usr/bin/python3
"""decode.py - draws, as a PBM image, what a stream of Star raster commands
tells the printer to print, so it can be checked on screen before using paper.

Reads the commands rastertostarn writes (see the header of rastertostarn.c):
the "b nL nH data" lines and the "ESC * r Y n NUL" skips; the rest is only
listed. Refuses a stream with a truncated line of dots, or one that does not
end by closing the page and the document.

Usage: decode.py stream.bin output.pbm
"""
import sys

LINE_BYTES = 72     # 576 dots


def main():
    o = open(sys.argv[1], "rb").read()
    lines, others, i = [], [], 0
    while i < len(o):
        b = o[i]
        if b == 0x62:
            if i + 3 > len(o) or i + 3 + (o[i + 1] | (o[i + 2] << 8)) > len(o):
                sys.exit(f"truncated line of dots at offset {i}")
            n = o[i + 1] | (o[i + 2] << 8)
            lines.append(o[i + 3:i + 3 + n])
            i += 3 + n
        elif b == 0x1b and o[i + 1:i + 3] == b"*r":
            c = chr(o[i + 3])
            if c in "RAB":
                others.append("*r" + c)
                i += 4
            else:
                k = o.index(b"\x00", i + 4)
                v = o[i + 4:k].decode("ascii")
                i = k + 1
                if c == "Y":
                    lines.extend([b""] * int(v))
                else:
                    others.append(f"*r{c}{v}")
        elif b == 0x1b and o[i + 1] == 0x40:
            others.append("ESC@")
            i += 2
        elif b == 0x1b and o[i + 1] == 0x1e:
            others.append(f"RS{chr(o[i + 2])}{o[i + 3]}")
            i += 4
        elif b == 0x1b and o[i + 1] == 0x07:
            others.append(f"BEL{o[i + 2]},{o[i + 3]}")
            i += 4
        elif b == 0x1b and o[i + 1] == 0x0c:
            others.append("FF")
            i += 2
        elif b == 0x00:
            others.append("NUL")
            i += 1
        elif b == 0x04:
            others.append("EOT")
            i += 1
        else:
            sys.exit(f"unexpected byte {b:#04x} at offset {i}")
    if others[-3:] != ["FF", "EOT", "*rB"]:
        sys.exit(f"the stream does not end by closing the page and the document: {' '.join(others[-4:])}")
    with open(sys.argv[2], "wb") as f:
        f.write(b"P4\n%d %d\n" % (LINE_BYTES * 8, len(lines)))
        for line in lines:
            f.write(line[:LINE_BYTES].ljust(LINE_BYTES, b"\x00"))
    print(f"{len(lines)} lines ({len(lines) / 8:.1f} mm), {sum(1 for line in lines if line)} with dots | {' '.join(others)}")


if __name__ == "__main__":
    main()
