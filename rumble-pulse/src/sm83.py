"""Tiny SM83 (Game Boy CPU) emitter. Only the opcodes this project needs."""

R8 = {'b': 0, 'c': 1, 'd': 2, 'e': 3, 'h': 4, 'l': 5, 'hl': 6, 'a': 7}
CC = {'nz': 0, 'z': 1, 'nc': 2, 'c': 3}
RR = {'bc': 0, 'de': 1, 'hl': 2, 'sp': 3}
PP = {'bc': 0, 'de': 1, 'hl': 2, 'af': 3}


class Asm:
    def __init__(self, size=0x8000):
        self.rom = bytearray(size)
        self.pc = 0
        self.labels = {}
        self.fix = []
        self.scope = '_'

    # ---- plumbing -------------------------------------------------
    def org(self, a):
        self.pc = a
        return self

    def b(self, *vals):
        for v in vals:
            self.rom[self.pc] = v & 0xFF
            self.pc += 1
        return self

    def _full(self, n):
        return (self.scope + n) if n.startswith('.') else n

    def lab(self, n):
        if not n.startswith('.'):
            self.scope = n
        f = self._full(n)
        assert f not in self.labels, "dup label " + f
        self.labels[f] = self.pc
        return self

    def _w16(self, v):
        if isinstance(v, str):
            self.fix.append((self.pc, self._full(v), 'w'))
            self.b(0, 0)
        else:
            self.b(v & 0xFF, (v >> 8) & 0xFF)

    def _rel(self, v):
        if isinstance(v, str):
            self.fix.append((self.pc, self._full(v), 'r'))
            self.b(0)
        else:
            self.b(v)

    def resolve(self):
        for addr, name, kind in self.fix:
            assert name in self.labels, "undefined label " + name
            t = self.labels[name]
            if kind == 'w':
                self.rom[addr] = t & 0xFF
                self.rom[addr + 1] = (t >> 8) & 0xFF
            else:
                d = t - (addr + 1)
                assert -128 <= d <= 127, "jr out of range to %s (%d)" % (name, d)
                self.rom[addr] = d & 0xFF

    # ---- loads ----------------------------------------------------
    def ld(self, d, s):
        """ld reg,reg  or  ld reg,imm8"""
        if isinstance(s, str) and s in R8:
            assert not (d == 'hl' and s == 'hl')
            return self.b(0x40 | (R8[d] << 3) | R8[s])
        return self.b(0x06 | (R8[d] << 3), s)

    def ld16(self, rr, nn):
        return self.b(0x01 | (RR[rr] << 4))._w16(nn) or self

    def ld_a_abs(self, nn):
        self.b(0xFA)
        self._w16(nn)
        return self

    def ld_abs_a(self, nn):
        self.b(0xEA)
        self._w16(nn)
        return self

    def ldh_a(self, n):
        return self.b(0xF0, n)

    def ldh(self, n):
        return self.b(0xE0, n)

    def ldi_hl_a(self):
        return self.b(0x22)

    def ldi_a_hl(self):
        return self.b(0x2A)

    # ---- arithmetic ----------------------------------------------
    def inc(self, r):
        return self.b(0x04 | (R8[r] << 3))

    def dec(self, r):
        return self.b(0x05 | (R8[r] << 3))

    def inc16(self, rr):
        return self.b(0x03 | (RR[rr] << 4))

    def dec16(self, rr):
        return self.b(0x0B | (RR[rr] << 4))

    def add(self, s):
        return self.b(0x80 | R8[s]) if isinstance(s, str) else self.b(0xC6, s)

    def sub(self, s):
        return self.b(0x90 | R8[s]) if isinstance(s, str) else self.b(0xD6, s)

    def and_(self, s):
        return self.b(0xA0 | R8[s]) if isinstance(s, str) else self.b(0xE6, s)

    def or_(self, s):
        return self.b(0xB0 | R8[s]) if isinstance(s, str) else self.b(0xF6, s)

    def xor(self, s):
        return self.b(0xA8 | R8[s]) if isinstance(s, str) else self.b(0xEE, s)

    def cp(self, s):
        return self.b(0xB8 | R8[s]) if isinstance(s, str) else self.b(0xFE, s)

    def add_hl(self, rr):
        return self.b(0x09 | (RR[rr] << 4))

    def cpl(self):
        return self.b(0x2F)

    def swap(self, r):
        return self.b(0xCB, 0x30 | R8[r])

    def rlca(self):
        return self.b(0x07)

    def rr(self, r):
        return self.b(0xCB, 0x18 | R8[r])

    def srl(self, r):
        return self.b(0xCB, 0x38 | R8[r])

    def bit(self, n, r):
        return self.b(0xCB, 0x40 | (n << 3) | R8[r])

    def set_(self, n, r):
        return self.b(0xCB, 0xC0 | (n << 3) | R8[r])

    def res(self, n, r):
        return self.b(0xCB, 0x80 | (n << 3) | R8[r])

    # ---- flow -----------------------------------------------------
    def jr(self, t, cc=None):
        self.b(0x18 if cc is None else 0x20 | (CC[cc] << 3))
        self._rel(t)
        return self

    def jp(self, t, cc=None):
        self.b(0xC3 if cc is None else 0xC2 | (CC[cc] << 3))
        self._w16(t)
        return self

    def call(self, t, cc=None):
        self.b(0xCD if cc is None else 0xC4 | (CC[cc] << 3))
        self._w16(t)
        return self

    def ret(self, cc=None):
        return self.b(0xC9 if cc is None else 0xC0 | (CC[cc] << 3))

    def push(self, rr):
        return self.b(0xC5 | (PP[rr] << 4))

    def pop(self, rr):
        return self.b(0xC1 | (PP[rr] << 4))

    def di(self):
        return self.b(0xF3)

    def nop(self):
        return self.b(0x00)

    def halt(self):
        return self.b(0x76)

    def ascii(self, s, term=True):
        for ch in s:
            self.b(ord(ch))
        if term:
            self.b(0)
        return self
