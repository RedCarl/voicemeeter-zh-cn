# -*- coding: utf-8 -*-
"""Minimal PE / string-pool helpers used by build_mempatch.py.

Only the standard library is required, so the builder runs on a bare Python
install (no pip packages).

Vocabulary used throughout:
  * literal   - a NUL-terminated string inside the executable. VoiceMeeter keeps
                them in a mixed pool: plain ANSI (drawn with TextOutA/DrawTextA)
                and UTF-16LE (drawn with DrawTextW).
  * span      - the byte range a literal may safely occupy. See Spans.safe_span()
                for why the naive "up to the next literal" answer is wrong.
"""
import bisect
import struct
import unicodedata


# --------------------------------------------------------------------------- PE
class PE:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.data = f.read()
        d = self.data
        e_lfanew = struct.unpack_from("<I", d, 0x3C)[0]
        if d[e_lfanew:e_lfanew + 4] != b"PE\0\0":
            raise ValueError("不是有效的 PE 文件")
        coff = e_lfanew + 4
        nsec, = struct.unpack_from("<H", d, coff + 2)
        optsize, = struct.unpack_from("<H", d, coff + 16)
        opt = coff + 20
        self.ddoff = opt
        magic, = struct.unpack_from("<H", d, opt)
        self.is_64 = magic == 0x20B
        self.image_base, = struct.unpack_from("<Q", d, opt + 24)
        self.sections = []
        soff = opt + optsize
        for i in range(nsec):
            s = soff + i * 40
            name = d[s:s + 8].rstrip(b"\0").decode("latin1")
            vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", d, s + 8)
            self.sections.append((name, vaddr, vsize, raddr, rsize))

    @property
    def size(self):
        return len(self.data)

    def rva2off(self, rva):
        for name, vaddr, vsize, raddr, rsize in self.sections:
            if vaddr <= rva < vaddr + max(vsize, rsize):
                return raddr + (rva - vaddr)
        return None

    def off2rva(self, off):
        for name, vaddr, vsize, raddr, rsize in self.sections:
            if raddr <= off < raddr + rsize:
                return vaddr + (off - raddr)
        return None

    def section_of(self, off):
        for name, vaddr, vsize, raddr, rsize in self.sections:
            if raddr <= off < raddr + rsize:
                return name.strip()
        return None

    def in_rdata(self, off):
        return self.section_of(off) == ".rdata"

    def checksum_field(self):
        return self.ddoff + 64

    def compute_checksum(self):
        """Standard PE image checksum (checksum field treated as zero)."""
        d = self.data
        off = self.checksum_field()
        total = 0
        i = 0
        n = len(d)
        while i < n:
            if off <= i < off + 4:
                i = off + 4
                continue
            if i + 1 < n:
                w, = struct.unpack_from("<H", d, i)
                i += 2
            else:
                w = d[i]
                i += 1
            total += w
            total = (total & 0xFFFF) + (total >> 16)
        total = (total & 0xFFFF) + (total >> 16)
        return (total + n) & 0xFFFFFFFF

    def stored_checksum(self):
        return struct.unpack_from("<I", self.data, self.checksum_field())[0]


# --------------------------------------------------------------------- literals
def _printable_wide(cp):
    return (0x20 <= cp <= 0x7E or 0xA0 <= cp <= 0x24F
            or 0x3000 <= cp <= 0x9FFF or 0xFF00 <= cp <= 0xFFEF)


def collect_starts(d):
    """Every ANSI and UTF-16 literal start in the image.

    A literal starts right after a NUL (0x00 for ANSI, 0x0000 for UTF-16), which
    automatically excludes suffix-pooled substrings: those begin in the middle of
    another literal and therefore have a normal character in front of them.
    """
    starts = set()
    n = len(d)
    i = 0
    while i < n - 3:
        if 32 <= d[i] < 127 and (i == 0 or d[i - 1] == 0):
            j = i
            while j < n and 32 <= d[j] < 127:
                j += 1
            if j < n and d[j] == 0 and j - i >= 2:
                starts.add(i)
            i = j
        else:
            i += 1
    i = 0
    while i < n - 6:
        if d[i:i + 2] == b"\x00\x00" and (i + 2) % 2 == 0:
            s = i + 2
            p = s
            cnt = 0
            ok = True
            while p < n - 1:
                u, = struct.unpack_from("<H", d, p)
                if u == 0:
                    break
                if not _printable_wide(u):
                    ok = False
                    break
                cnt += 1
                p += 2
            if ok and cnt >= 3:
                starts.add(s)
                i = p + 2
                continue
        i += 1
    return sorted(starts)


class Spans:
    """String-start index plus the safe write range for each literal."""

    def __init__(self, data):
        self.starts = collect_starts(data)

    def next_start(self, off):
        k = bisect.bisect_right(self.starts, off)
        return self.starts[k] if k < len(self.starts) else None

    def safe_span(self, d, off, olit):
        """End of the byte range a literal at `off` may occupy.

        The range is the literal's own bytes plus the run of NUL bytes that
        immediately follows its terminator, capped at the next literal start.

        The trailing-NUL cap is essential.  In `.data`, VoiceMeeter stores
        fixed-size records such as

            0x180170  'BUS A1' \\0  <121 more NUL>  <8 bytes of real data>

        Zero-filling all the way to the next literal start wipes that trailing
        field and the application crashes on startup (reproduced).
        """
        lim = self.next_start(off)
        end = off + olit + 1
        hard = lim if lim is not None else len(d)
        while end < hard and d[end] == 0:
            end += 1
        return end

    def safe_avail(self, d, off, olit):
        return self.safe_span(d, off, olit) - off


def find_literal(d, text, kind, require_nul_before=True):
    """Offsets where `text` occurs as a complete literal of the given kind.

    kind 'A' = ANSI (bytes + NUL), 'W' = UTF-16LE (units + 0x0000).

    A byte-pattern search is used instead of walking the string inventory: the
    inventory's traversal can skip literals in regions that mix ANSI and UTF-16
    (verified on Potato's 'Fader Gain'), while a search never misses one.
    """
    if kind == "A":
        body = text.encode("latin1")
        term = b"\x00"
    else:
        body = text.encode("utf-16le")
        term = b"\x00\x00"
    head = term
    pat = body + term
    out = []
    st = 0
    while True:
        i = d.find(pat, st)
        if i < 0:
            break
        if not require_nul_before or (i >= len(head) and d[i - len(head):i] == head):
            out.append(i)
        st = i + 1
    return out


def display_width(s):
    """Rough on-screen width: CJK glyphs take about twice a Latin character."""
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
               for ch in s)
