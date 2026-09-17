"""Headless SM83 interpreter covering the opcode subset this ROM uses.
Used to validate rumble register timing without hardware or an emulator."""


class GB:
    def __init__(self, rom):
        self.rom = bytes(rom)
        self.vram = bytearray(0x2000)
        self.wram = bytearray(0x2000)
        self.hram = bytearray(0x100)
        self.a = self.b = self.c = self.d = self.e = self.h = self.l = 0
        self.fz = self.fn = self.fh = self.fc = 0
        self.sp = 0xFFFE
        self.pc = 0x100
        self.cyc = 0
        self.next_tick = 1024
        self.iflag = 0
        self.p1sel = 0x30
        self.keys = 0          # bit0 A,1 B,2 SEL,3 START,4 R,5 L,6 U,7 D
        self.rumble = 0
        self.log = []          # (cycle, on/off)
        self.stat_mode = 0

    # ---- memory ----
    def rb(self, addr):
        addr &= 0xFFFF
        if addr < 0x8000:
            return self.rom[addr]
        if addr < 0xA000:
            return self.vram[addr - 0x8000]
        if 0xC000 <= addr < 0xE000:
            return self.wram[addr - 0xC000]
        if addr >= 0xFF00:
            return self.io_r(addr)
        return 0xFF

    def wb(self, addr, v):
        addr &= 0xFFFF
        v &= 0xFF
        if addr < 0x8000:
            if 0x4000 <= addr < 0x6000:
                on = 1 if (v & 8) else 0
                if on != self.rumble:
                    self.rumble = on
                    self.log.append((self.cyc, on))
            return
        if addr < 0xA000:
            self.vram[addr - 0x8000] = v
            return
        if 0xC000 <= addr < 0xE000:
            self.wram[addr - 0xC000] = v
            return
        if addr >= 0xFF00:
            self.io_w(addr, v)

    def io_r(self, addr):
        lo = addr & 0xFF
        if lo == 0x00:   # P1
            out = self.p1sel | 0x0F
            if not (self.p1sel & 0x10):          # directions selected
                out &= ~((self.keys >> 4) & 0x0F) & 0xFF
                out |= self.p1sel & 0x30
            if not (self.p1sel & 0x20):          # buttons selected
                out &= ~(self.keys & 0x0F) & 0xFF
                out |= self.p1sel & 0x30
            return (out & 0x3F) | 0xC0
        if lo == 0x0F:
            self.sync_timer()
            return self.iflag | 0xE0
        if lo == 0x41:
            return self.stat_mode
        if lo == 0x44:
            return (self.cyc // 456) % 154
        return self.hram[lo]

    def io_w(self, addr, v):
        lo = addr & 0xFF
        if lo == 0x00:
            self.p1sel = v & 0x30
            return
        if lo == 0x0F:
            self.iflag = v & 0x1F
            return
        self.hram[lo] = v

    def sync_timer(self):
        while self.cyc >= self.next_tick:
            self.iflag |= 0x04
            self.next_tick += 1024

    # ---- helpers ----
    def f(self):
        return (self.fz << 7) | (self.fn << 6) | (self.fh << 5) | (self.fc << 4)

    def setf(self, v):
        self.fz = (v >> 7) & 1
        self.fn = (v >> 6) & 1
        self.fh = (v >> 5) & 1
        self.fc = (v >> 4) & 1

    def get_r(self, i):
        return [self.b, self.c, self.d, self.e, self.h, self.l,
                self.rb((self.h << 8) | self.l), self.a][i]

    def set_r(self, i, v):
        v &= 0xFF
        if i == 0:
            self.b = v
        elif i == 1:
            self.c = v
        elif i == 2:
            self.d = v
        elif i == 3:
            self.e = v
        elif i == 4:
            self.h = v
        elif i == 5:
            self.l = v
        elif i == 6:
            self.wb((self.h << 8) | self.l, v)
        else:
            self.a = v

    def imm8(self):
        v = self.rb(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def imm16(self):
        lo = self.imm8()
        hi = self.imm8()
        return (hi << 8) | lo

    def push16(self, v):
        self.sp = (self.sp - 1) & 0xFFFF
        self.wb(self.sp, (v >> 8) & 0xFF)
        self.sp = (self.sp - 1) & 0xFFFF
        self.wb(self.sp, v & 0xFF)

    def pop16(self):
        lo = self.rb(self.sp)
        self.sp = (self.sp + 1) & 0xFFFF
        hi = self.rb(self.sp)
        self.sp = (self.sp + 1) & 0xFFFF
        return (hi << 8) | lo

    def cond(self, i):
        return [not self.fz, self.fz, not self.fc, self.fc][i]

    def alu(self, op, v):
        a = self.a
        if op == 0:      # add
            r = a + v
            self.fh = ((a & 15) + (v & 15)) > 15
            self.fc = r > 255
            self.a = r & 0xFF
            self.fn = 0
        elif op == 1:    # adc
            cin = self.fc
            r = a + v + cin
            self.fh = ((a & 15) + (v & 15) + cin) > 15
            self.fc = r > 255
            self.a = r & 0xFF
            self.fn = 0
        elif op in (2, 7):   # sub / cp
            r = a - v
            self.fh = (a & 15) < (v & 15)
            self.fc = r < 0
            self.fn = 1
            if op == 2:
                self.a = r & 0xFF
            self.fz = 1 if (r & 0xFF) == 0 else 0
            self.fh = 1 if self.fh else 0
            self.fc = 1 if self.fc else 0
            return
        elif op == 3:    # sbc
            cin = self.fc
            r = a - v - cin
            self.fh = (a & 15) < ((v & 15) + cin)
            self.fc = r < 0
            self.a = r & 0xFF
            self.fn = 1
        elif op == 4:    # and
            self.a = a & v
            self.fn = 0
            self.fh = 1
            self.fc = 0
        elif op == 5:    # xor
            self.a = a ^ v
            self.fn = self.fh = self.fc = 0
        elif op == 6:    # or
            self.a = a | v
            self.fn = self.fh = self.fc = 0
        self.fz = 1 if self.a == 0 else 0
        self.fh = 1 if self.fh else 0
        self.fc = 1 if self.fc else 0

    # ---- step ----
    def step(self):
        op = self.imm8()
        c = 4

        if op == 0x00:
            pass
        elif op == 0xF3 or op == 0xFB:
            pass
        elif op == 0x2F:
            self.a ^= 0xFF
            self.fn = self.fh = 1
        elif op == 0x0F:  # rrca
            self.fc = self.a & 1
            self.a = ((self.a >> 1) | (self.fc << 7)) & 0xFF
            self.fz = self.fn = self.fh = 0
        elif op == 0x07:  # rlca
            self.fc = (self.a >> 7) & 1
            self.a = ((self.a << 1) | self.fc) & 0xFF
            self.fz = self.fn = self.fh = 0
        elif 0x40 <= op <= 0x7F and op != 0x76:
            d = (op >> 3) & 7
            s = op & 7
            self.set_r(d, self.get_r(s))
            c = 8 if (d == 6 or s == 6) else 4
        elif (op & 0xC7) == 0x06:      # ld r,n
            self.set_r((op >> 3) & 7, self.imm8())
            c = 8
        elif op in (0x01, 0x11, 0x21, 0x31):
            v = self.imm16()
            if op == 0x01:
                self.b, self.c = v >> 8, v & 0xFF
            elif op == 0x11:
                self.d, self.e = v >> 8, v & 0xFF
            elif op == 0x21:
                self.h, self.l = v >> 8, v & 0xFF
            else:
                self.sp = v
            c = 12
        elif op == 0xFA:
            self.a = self.rb(self.imm16())
            c = 16
        elif op == 0xEA:
            self.wb(self.imm16(), self.a)
            c = 16
        elif op == 0xF0:
            self.a = self.rb(0xFF00 + self.imm8())
            c = 12
        elif op == 0xE0:
            self.wb(0xFF00 + self.imm8(), self.a)
            c = 12
        elif op == 0x1A:
            self.a = self.rb((self.d << 8) | self.e)
            c = 8
        elif op == 0x22:
            hl = (self.h << 8) | self.l
            self.wb(hl, self.a)
            hl = (hl + 1) & 0xFFFF
            self.h, self.l = hl >> 8, hl & 0xFF
            c = 8
        elif op == 0x2A:
            hl = (self.h << 8) | self.l
            self.a = self.rb(hl)
            hl = (hl + 1) & 0xFFFF
            self.h, self.l = hl >> 8, hl & 0xFF
            c = 8
        elif (op & 0xC7) == 0x04:      # inc r
            i = (op >> 3) & 7
            v = (self.get_r(i) + 1) & 0xFF
            self.set_r(i, v)
            self.fz = 1 if v == 0 else 0
            self.fn = 0
            self.fh = 1 if (v & 15) == 0 else 0
        elif (op & 0xC7) == 0x05:      # dec r
            i = (op >> 3) & 7
            v = (self.get_r(i) - 1) & 0xFF
            self.set_r(i, v)
            self.fz = 1 if v == 0 else 0
            self.fn = 1
            self.fh = 1 if (v & 15) == 15 else 0
        elif op in (0x03, 0x13, 0x23, 0x33):
            if op == 0x03:
                v = (((self.b << 8) | self.c) + 1) & 0xFFFF
                self.b, self.c = v >> 8, v & 0xFF
            elif op == 0x13:
                v = (((self.d << 8) | self.e) + 1) & 0xFFFF
                self.d, self.e = v >> 8, v & 0xFF
            elif op == 0x23:
                v = (((self.h << 8) | self.l) + 1) & 0xFFFF
                self.h, self.l = v >> 8, v & 0xFF
            else:
                self.sp = (self.sp + 1) & 0xFFFF
            c = 8
        elif op in (0x0B, 0x1B, 0x2B, 0x3B):
            if op == 0x0B:
                v = (((self.b << 8) | self.c) - 1) & 0xFFFF
                self.b, self.c = v >> 8, v & 0xFF
            elif op == 0x1B:
                v = (((self.d << 8) | self.e) - 1) & 0xFFFF
                self.d, self.e = v >> 8, v & 0xFF
            elif op == 0x2B:
                v = (((self.h << 8) | self.l) - 1) & 0xFFFF
                self.h, self.l = v >> 8, v & 0xFF
            else:
                self.sp = (self.sp - 1) & 0xFFFF
            c = 8
        elif 0x80 <= op <= 0xBF:
            self.alu((op >> 3) & 7, self.get_r(op & 7))
            c = 8 if (op & 7) == 6 else 4
        elif op in (0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE):
            self.alu((op >> 3) & 7, self.imm8())
            c = 8
        elif op in (0x09, 0x19, 0x29, 0x39):
            hl = (self.h << 8) | self.l
            rr = {0x09: (self.b << 8) | self.c, 0x19: (self.d << 8) | self.e,
                  0x29: hl, 0x39: self.sp}[op]
            r = hl + rr
            self.fn = 0
            self.fh = 1 if ((hl & 0xFFF) + (rr & 0xFFF)) > 0xFFF else 0
            self.fc = 1 if r > 0xFFFF else 0
            r &= 0xFFFF
            self.h, self.l = r >> 8, r & 0xFF
            c = 8
        elif op == 0x18:
            o = self.imm8()
            self.pc = (self.pc + (o - 256 if o > 127 else o)) & 0xFFFF
            c = 12
        elif op in (0x20, 0x28, 0x30, 0x38):
            o = self.imm8()
            if self.cond((op >> 3) & 3):
                self.pc = (self.pc + (o - 256 if o > 127 else o)) & 0xFFFF
                c = 12
            else:
                c = 8
        elif op == 0xC3:
            self.pc = self.imm16()
            c = 16
        elif op in (0xC2, 0xCA, 0xD2, 0xDA):
            t = self.imm16()
            if self.cond((op >> 3) & 3):
                self.pc = t
                c = 16
            else:
                c = 12
        elif op == 0xE9:
            self.pc = (self.h << 8) | self.l
        elif op == 0xCD:
            t = self.imm16()
            self.push16(self.pc)
            self.pc = t
            c = 24
        elif op in (0xC4, 0xCC, 0xD4, 0xDC):
            t = self.imm16()
            if self.cond((op >> 3) & 3):
                self.push16(self.pc)
                self.pc = t
                c = 24
            else:
                c = 12
        elif op == 0xC9:
            self.pc = self.pop16()
            c = 16
        elif op in (0xC0, 0xC8, 0xD0, 0xD8):
            if self.cond((op >> 3) & 3):
                self.pc = self.pop16()
                c = 20
            else:
                c = 8
        elif op in (0xC5, 0xD5, 0xE5, 0xF5):
            v = {0xC5: (self.b << 8) | self.c, 0xD5: (self.d << 8) | self.e,
                 0xE5: (self.h << 8) | self.l, 0xF5: (self.a << 8) | self.f()}[op]
            self.push16(v)
            c = 16
        elif op in (0xC1, 0xD1, 0xE1, 0xF1):
            v = self.pop16()
            if op == 0xC1:
                self.b, self.c = v >> 8, v & 0xFF
            elif op == 0xD1:
                self.d, self.e = v >> 8, v & 0xFF
            elif op == 0xE1:
                self.h, self.l = v >> 8, v & 0xFF
            else:
                self.a = v >> 8
                self.setf(v & 0xF0)
            c = 12
        elif op == 0xCB:
            cb = self.imm8()
            i = cb & 7
            v = self.get_r(i)
            grp = cb >> 6
            n = (cb >> 3) & 7
            if grp == 1:       # bit
                self.fz = 0 if (v >> n) & 1 else 1
                self.fn = 0
                self.fh = 1
            elif grp == 2:     # res
                self.set_r(i, v & ~(1 << n))
            elif grp == 3:     # set
                self.set_r(i, v | (1 << n))
            else:
                if n == 6:     # swap
                    r = ((v << 4) | (v >> 4)) & 0xFF
                    self.set_r(i, r)
                    self.fz = 1 if r == 0 else 0
                    self.fn = self.fh = self.fc = 0
                elif n == 3:   # rr
                    cin = self.fc
                    self.fc = v & 1
                    r = (v >> 1) | (cin << 7)
                    self.set_r(i, r)
                    self.fz = 1 if r == 0 else 0
                    self.fn = self.fh = 0
                elif n == 2:   # rl
                    cin = self.fc
                    self.fc = (v >> 7) & 1
                    r = ((v << 1) | cin) & 0xFF
                    self.set_r(i, r)
                    self.fz = 1 if r == 0 else 0
                    self.fn = self.fh = 0
                elif n == 7:   # srl
                    self.fc = v & 1
                    r = v >> 1
                    self.set_r(i, r)
                    self.fz = 1 if r == 0 else 0
                    self.fn = self.fh = 0
                else:
                    raise Exception("unhandled CB %02X" % cb)
            c = 8
        else:
            raise Exception("unhandled opcode %02X at %04X" % (op, self.pc - 1))

        self.cyc += c
        return c
