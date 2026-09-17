#!/usr/bin/env python3
"""Assemble RUMBLE PULSE TEST into a 32 KiB MBC5+RUMBLE .gb image.

Bit length is expressed in LCD frames by default -- the only cadence a real
game can produce from a VBlank handler -- with an optional millisecond mode
for sub-frame threshold hunting.
"""

import os

from sm83 import Asm
import font

# Paths hang off this file rather than the working directory, so the build and
# the renderer land in the same place from wherever they are run.
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ROM_PATH = os.path.join(ROOT, 'rumble-pulse.gb')
SHOT_DIR = os.path.join(ROOT, 'screenshots')

# ---- hardware ---------------------------------------------------------
rIF, rLCDC, rSTAT, rSCY, rSCX, rLY, rBGP = 0x0F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x47
rP1, rTIMA, rTMA, rTAC = 0x00, 0x05, 0x06, 0x07
RUMBLE = 0x4000

# ---- WRAM -------------------------------------------------------------
pattern, cursor, blen_ms, mode, prespin = 0xC000, 0xC001, 0xC002, 0xC003, 0xC004
sweepn, result, keys, prev, pressed = 0xC005, 0xC006, 0xC007, 0xC008, 0xC009
btk = 0xC00A                 # 2 bytes
numbuf = 0xC00C              # 4 bytes
repctr, running, sticky = 0xC010, 0xC011, 0xC012
tmpA, tmpB, tmpB2, tmpC, tmpD = 0xC013, 0xC014, 0xC015, 0xC016, 0xC017
unit, blen_fr = 0xC018, 0xC019          # unit: 0 = frames, 1 = ms
duration, runcount = 0xC01A, 0xC01B     # burst length in bits, 0 = continuous
gap, gapcount = 0xC01C, 0xC01D          # rest between bursts, 0 = single burst
presetn = 0xC01E

K_A, K_B, K_SEL, K_START = 0x01, 0x02, 0x04, 0x08
K_RIGHT, K_LEFT, K_UP, K_DOWN = 0x10, 0x20, 0x40, 0x80


def MAP(x, y):
    return 0x9800 + y * 32 + x


a = Asm(0x8000)


def ldhl(x, y):
    v = MAP(x, y)
    a.b(0x21).b(v & 0xFF, v >> 8)


def pstr(x, y, lbl):
    ldhl(x, y)
    a.ld16('de', lbl)
    a.call('print')


def pnum(x, y):
    ldhl(x, y)
    a.call('printn4')


def pdim(x, y, lbl):
    ldhl(x, y)
    a.ld16('de', lbl)
    a.call('print_d')


# ---- entry + header ---------------------------------------------------
a.org(0x100).nop().jp('start')
a.org(0x104).b(
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83,
    0x00, 0x0C, 0x00, 0x0D, 0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
    0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99, 0xBB, 0xBB, 0x67, 0x63,
    0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E)
a.org(0x134)
title = "RUMBLEPULSE"
for i in range(16):
    a.b(ord(title[i]) if i < len(title) else 0)
a.org(0x144).b(0x00, 0x00, 0x00)
a.b(0x1C)      # MBC5 + RUMBLE
a.b(0x00)      # 32 KiB
a.b(0x00)      # no RAM
a.b(0x01)
a.b(0x33)
a.b(0x00)
a.b(0x00)
a.b(0x00, 0x00)

# ---- init -------------------------------------------------------------
a.org(0x150)
a.lab('start')
a.di()
a.b(0x31, 0xFE, 0xFF)
a.lab('.vb').ldh_a(rLY).cp(144).jr('.vb', 'nz')
a.ld('a', 0).ldh(rLCDC)

a.b(0x21).b(0x00, 0x80)
a.ld16('de', 'fontdata')
a.ld16('bc', 3328)
a.lab('.fc')
a.b(0x1A)
a.ldi_hl_a().inc16('de').dec16('bc')
a.ld('a', 'b').or_('c').jr('.fc', 'nz')

a.b(0x21).b(0x00, 0x98)
a.ld16('bc', 0x0400)
a.lab('.cm')
a.xor('a').ldi_hl_a().dec16('bc')
a.ld('a', 'b').or_('c').jr('.cm', 'nz')

a.call('draw_frame')
a.ld('a', 0xE4).ldh(rBGP)
a.xor('a').ldh(rSCX).xor('a').ldh(rSCY)

a.ld('a', 0xFF).ldh(rTMA)
a.ld('a', 0xFF).ldh(rTIMA)
a.ld('a', 0x04).ldh(rTAC)            # 4096 Hz

a.ld('a', 0x55).ld_abs_a(pattern)       # Pinball options demo pattern
a.xor('a').ld_abs_a(cursor)
a.xor('a').ld_abs_a(unit)            # frames
a.ld('a', 1).ld_abs_a(blen_fr)
a.ld('a', 17).ld_abs_a(blen_ms)
a.xor('a').ld_abs_a(mode)
a.xor('a').ld_abs_a(prespin)
a.ld('a', 1).ld_abs_a(sweepn)
a.ld('a', 64).ld_abs_a(duration)         # Pinball runs 64 frames
a.xor('a').ld_abs_a(gap)
a.xor('a').ld_abs_a(presetn)
a.xor('a').ld_abs_a(result)
a.xor('a').ld_abs_a(prev)
a.xor('a').ld_abs_a(running)
a.xor('a').ld_abs_a(sticky)
a.xor('a').ld_abs_a(repctr)
a.xor('a').ld_abs_a(RUMBLE)

a.ld('a', 0x91).ldh(rLCDC)
a.call('draw_all')

# ---- main loop --------------------------------------------------------
a.lab('main')
a.call('waitframe')
a.call('readkeys')
a.xor('a').ld_abs_a(sticky)
a.call('autorepeat')
a.ld_a_abs(pressed).or_('a').jp('main', 'z')
a.ld('b', 'a')
a.ld_a_abs(keys).and_(K_SEL).jr('.normal', 'z')
a.ld('a', 'b')
a.bit(0, 'a').jp('h_unit', 'nz')
a.bit(1, 'a').jp('h_prespin', 'nz')
a.bit(3, 'a').jp('h_start', 'nz')
a.bit(6, 'a').jp('h_dur_up', 'nz')
a.bit(7, 'a').jp('h_dur_down', 'nz')
a.bit(4, 'a').jp('h_gap_up', 'nz')
a.bit(5, 'a').jp('h_gap_down', 'nz')
a.jp('main')
a.lab('.normal')
a.ld('a', 'b')
a.bit(3, 'a').jp('h_start', 'nz')
a.bit(1, 'a').jp('h_mode', 'nz')
a.bit(0, 'a').jp('h_a', 'nz')
a.bit(5, 'a').jp('h_left', 'nz')
a.bit(4, 'a').jp('h_right', 'nz')
a.bit(6, 'a').jp('h_up', 'nz')
a.bit(7, 'a').jp('h_down', 'nz')
a.jp('main')

a.lab('h_start')
a.ld('a', 1).ld_abs_a(running)
a.call('draw_all')
a.call('run_current')
a.xor('a').ld_abs_a(running)
a.call('draw_all')
a.jp('main')

a.lab('h_unit')
a.ld_a_abs(unit).xor(1).ld_abs_a(unit)
a.call('draw_all').jp('main')

a.lab('h_prespin')
a.ld_a_abs(prespin).xor(1).ld_abs_a(prespin)
a.call('draw_all').jp('main')

a.lab('h_dur_up')
a.call('burst_ok').jp('main', 'z')
a.ld_a_abs(duration).cp(200).jp('main', 'nc')
a.inc('a').ld_abs_a(duration)
a.call('draw_all').jp('main')

a.lab('h_dur_down')
a.call('burst_ok').jp('main', 'z')
a.ld_a_abs(duration).or_('a').jp('main', 'z')
a.dec('a').ld_abs_a(duration)
a.call('draw_all').jp('main')

a.lab('h_gap_up')
a.call('burst_ok').jp('main', 'z')
a.ld_a_abs(gap).cp(200).jp('main', 'nc')
a.inc('a').ld_abs_a(gap)
a.call('draw_all').jp('main')

a.lab('h_gap_down')
a.call('burst_ok').jp('main', 'z')
a.ld_a_abs(gap).or_('a').jp('main', 'z')
a.dec('a').ld_abs_a(gap)
a.call('draw_all').jp('main')

a.lab('h_mode')
a.ld_a_abs(mode).inc('a').cp(4).jr('.ok', 'c').xor('a')
a.lab('.ok').ld_abs_a(mode)
a.ld('a', 1).ld_abs_a(sweepn)
a.ld_a_abs(mode).cp(3).call('apply_preset', 'z')   # entering PRESET applies it
a.call('draw_all').jp('main')

a.lab('h_a')
a.ld_a_abs(mode).cp(3).jr('.nopre', 'nz')
a.call('apply_preset')
a.xor('a').ld_abs_a(mode)
a.call('draw_all').jp('main')
a.lab('.nopre')
a.ld_a_abs(mode).or_('a').jp('main', 'nz')
a.ld_a_abs(cursor).ld('b', 'a')
a.ld('a', 0x01).inc('b').jr('.t')
a.lab('.l').add('a')
a.lab('.t').dec('b').jr('.l', 'nz')
a.ld('b', 'a')
a.ld_a_abs(pattern).xor('b').ld_abs_a(pattern)
a.call('draw_all').jp('main')

a.lab('h_left')
a.ld_a_abs(mode).or_('a').jp('main', 'nz')
a.ld_a_abs(cursor).dec('a').and_(7).ld_abs_a(cursor)
a.call('draw_all').jp('main')

a.lab('h_right')
a.ld_a_abs(mode).or_('a').jp('main', 'nz')
a.ld_a_abs(cursor).inc('a').and_(7).ld_abs_a(cursor)
a.call('draw_all').jp('main')

a.lab('h_up')
a.ld_a_abs(mode).cp(3).jr('.notp', 'nz')
a.ld_a_abs(presetn).cp(9).jp('main', 'nc')
a.inc('a').ld_abs_a(presetn)
a.call('apply_preset').call('draw_all').jp('main')
a.lab('.notp')
a.ld_a_abs(unit).or_('a').jr('.ms', 'nz')
a.ld_a_abs(blen_fr).cp(16).jp('main', 'nc')
a.inc('a').ld_abs_a(blen_fr).jr('.d')
a.lab('.ms')
a.ld_a_abs(blen_ms).cp(99).jp('main', 'nc')
a.inc('a').ld_abs_a(blen_ms)
a.lab('.d').call('draw_all').jp('main')

a.lab('h_down')
a.ld_a_abs(mode).cp(3).jr('.notp', 'nz')
a.ld_a_abs(presetn).or_('a').jp('main', 'z')
a.dec('a').ld_abs_a(presetn)
a.call('apply_preset').call('draw_all').jp('main')
a.lab('.notp')
a.ld_a_abs(unit).or_('a').jr('.ms', 'nz')
a.ld_a_abs(blen_fr).cp(2).jp('main', 'c')
a.dec('a').ld_abs_a(blen_fr).jr('.d')
a.lab('.ms')
a.ld_a_abs(blen_ms).cp(2).jp('main', 'c')
a.dec('a').ld_abs_a(blen_ms)
a.lab('.d').call('draw_all').jp('main')

# ---- input ------------------------------------------------------------
a.lab('waitframe')
a.lab('.w1').ldh_a(rLY).cp(144).jr('.w1', 'z')
a.lab('.w2').ldh_a(rLY).cp(144).jr('.w2', 'nz')
a.ret()

a.lab('waitframe_k')
a.call('waitframe').call('readkeys').ret()

a.lab('readkeys')
a.push('bc').push('hl')
a.ld('a', 0x20).ldh(rP1)
a.ldh_a(rP1).ldh_a(rP1).ldh_a(rP1)
a.cpl().and_(0x0F).swap('a').ld('b', 'a')
a.ld('a', 0x10).ldh(rP1)
a.ldh_a(rP1).ldh_a(rP1).ldh_a(rP1).ldh_a(rP1).ldh_a(rP1).ldh_a(rP1)
a.cpl().and_(0x0F).or_('b').ld('c', 'a')
a.ld('a', 0x30).ldh(rP1)
a.ld('a', 'c').ld_abs_a(keys)
a.ld_a_abs(prev).cpl().and_('c').ld_abs_a(pressed)
a.ld('a', 'c').ld_abs_a(prev)
a.ld_a_abs(pressed).ld('b', 'a')
a.ld_a_abs(sticky).or_('b').ld_abs_a(sticky)
a.pop('hl').pop('bc')
a.ret()

a.lab('autorepeat')
a.ld_a_abs(keys).and_(K_UP | K_DOWN | K_LEFT | K_RIGHT).jr('.held', 'nz')
a.xor('a').ld_abs_a(repctr).ret()
a.lab('.held')
a.ld_a_abs(repctr).inc('a').ld_abs_a(repctr)
a.cp(20).ret('c')
a.and_(3).ret('nz')
a.ld_a_abs(keys).and_(K_UP | K_DOWN).ld('b', 'a')
a.ld_a_abs(keys).and_(K_SEL).jr('.nosel', 'z')
a.ld_a_abs(keys).and_(K_UP | K_DOWN | K_LEFT | K_RIGHT).ld('b', 'a')
a.lab('.nosel')
a.ld_a_abs(pressed).or_('b').ld_abs_a(pressed)
a.ret()

# ---- motor / timing ---------------------------------------------------
a.lab('motor_on')
a.ld('a', 0x08).ld_abs_a(RUMBLE).ret()

a.lab('motor_off')
a.xor('a').ld_abs_a(RUMBLE).ret()

a.lab('to_ticks')                     # A = ms -> DE ticks (4096 Hz)
a.ld_abs_a(tmpA)
a.ld('l', 'a').ld('h', 0)
a.add_hl('hl').add_hl('hl')
a.ld_a_abs(tmpA).ld('c', 0)
a.lab('.d').cp(10).jr('.dd', 'c').sub(10).inc('c').jr('.d')
a.lab('.dd').ld('b', 0).add_hl('bc')
a.ld('d', 'h').ld('e', 'l').ret()

a.lab('delay')                        # DE = ticks
a.ld('a', 'd').or_('e').ret('z')
a.lab('.l')
a.ldh_a(rIF).bit(2, 'a').jr('.l', 'z')
a.ldh_a(rIF).res(2, 'a').ldh(rIF)
a.push('de')
a.ld('a', 'e').and_(0x3F)
a.call('readkeys', 'z')
a.pop('de')
a.dec16('de')
a.ld('a', 'd').or_('e').jr('.l', 'nz')
a.ret()

a.lab('delay_ms')
a.call('to_ticks').call('delay').ret()

a.lab('set_btk')
a.ld_a_abs(blen_ms).call('to_ticks')
a.ld('a', 'e').ld_abs_a(btk)
a.ld('a', 'd').ld_abs_a(btk + 1)
a.ret()

a.lab('delay_one_bit')
a.ld_a_abs(unit).or_('a').jr('.ms', 'nz')
a.ld_a_abs(blen_fr).ld_abs_a(tmpD)
a.lab('.fl')
a.call('waitframe_k')
a.ld_a_abs(tmpD).dec('a').ld_abs_a(tmpD).jr('.fl', 'nz')
a.ret()
a.lab('.ms')
a.ld_a_abs(btk).ld('e', 'a')
a.ld_a_abs(btk + 1).ld('d', 'a')
a.call('delay')
a.call('readkeys')
a.ret()

a.lab('delay_bits')                   # A = number of bit slots
a.or_('a').ret('z')
a.ld_abs_a(tmpB)
a.lab('.l')
a.call('delay_one_bit')
a.ld_a_abs(tmpB).dec('a').ld_abs_a(tmpB).jr('.l', 'nz')
a.ret()

a.lab('sync_fr')
a.ld_a_abs(unit).or_('a').ret('nz')
a.call('waitframe').ret()

a.lab('prespin_do')
a.ld_a_abs(prespin).or_('a').ret('z')
a.call('motor_on')
a.ld('a', 250).call('delay_ms')
a.call('motor_off')
a.ld('a', 30).call('delay_ms')
a.ret()

a.lab('mul_hl_a')                     # HL = HL * A  (A small)
a.ld('d', 'h').ld('e', 'l')
a.b(0x21).b(0x00, 0x00)
a.or_('a').ret('z')
a.lab('.l').add_hl('de').dec('a').jr('.l', 'nz')
a.ret()

a.lab('get_bitms')                    # -> HL = effective ms per bit
a.ld_a_abs(unit).or_('a').jr('.ms', 'nz')
a.ld_a_abs(blen_fr).ld('l', 'a').ld('h', 0)
a.ld('d', 'h').ld('e', 'l')
for _ in range(6):
    a.add_hl('hl')                    # fr * 64
a.add_hl('de').add_hl('de').add_hl('de')   # fr * 67
a.ld16('de', 2).add_hl('de')
a.srl('h').rr('l').srl('h').rr('l')   # (fr*67 + 2) / 4  ~= fr * 16.742
a.ret()
a.lab('.ms')
a.ld_a_abs(blen_ms).ld('l', 'a').ld('h', 0)
a.ret()

# ---- run modes --------------------------------------------------------
a.lab('burst_ok')                     # NZ when RUN/GAP apply to this mode
a.ld_a_abs(mode).or_('a').jr('.yes', 'z')
a.cp(3).jr('.yes', 'z')
a.xor('a').ret()
a.lab('.yes').or_(1).ret()

a.lab('preset_addr')                  # HL = entry base for presetn
a.ld_a_abs(presetn).ld('l', 'a').ld('h', 0)
a.add_hl('hl').add_hl('hl').add_hl('hl').add_hl('hl')
a.ld16('de', 'presets').add_hl('de')
a.ret()

a.lab('apply_preset')
a.call('preset_addr')
a.ldi_a_hl().ld_abs_a(pattern)
a.ldi_a_hl().ld_abs_a(duration)
a.ldi_a_hl().ld_abs_a(gap)
a.ret()

a.lab('run_current')
a.xor('a').ld_abs_a(sticky)
a.call('set_btk')
a.ld_a_abs(mode).or_('a').jr('.m1', 'nz')
a.call('run_pattern').jr('.done')
a.lab('.m1').cp(1).jr('.m2', 'nz')
a.call('run_on_sweep').jr('.done')
a.lab('.m2').cp(2).jr('.m3', 'nz')
a.call('run_off_sweep').jr('.done')
a.lab('.m3').call('run_pattern')
a.lab('.done').call('motor_off').ret()

a.lab('run_pattern')
a.call('prespin_do')
a.lab('.burst')
a.call('sync_fr')
a.ld_a_abs(duration).ld_abs_a(runcount)
a.ld_a_abs(pattern).ld_abs_a(tmpC)
a.ld('a', 8).ld_abs_a(tmpB2)
a.lab('.nextbit')
a.ld_a_abs(tmpC).b(0x0F).ld_abs_a(tmpC)     # rrca: LSB first, as Pinball does
a.jr('.off', 'nc')
a.call('motor_on').jr('.dl')
a.lab('.off').call('motor_off')
a.lab('.dl')
a.call('delay_one_bit')
a.ld_a_abs(sticky).and_(K_START | K_B).jr('.stop', 'nz')
a.ld_a_abs(duration).or_('a').jr('.nodur', 'z')
a.ld_a_abs(runcount).dec('a').ld_abs_a(runcount).jr('.burstend', 'z')
a.lab('.nodur')
a.ld_a_abs(tmpB2).dec('a').ld_abs_a(tmpB2).jr('.nextbit', 'nz')
a.ld_a_abs(pattern).ld_abs_a(tmpC)
a.ld('a', 8).ld_abs_a(tmpB2)
a.jr('.nextbit')
a.lab('.burstend')
a.call('motor_off')
a.ld_a_abs(gap).or_('a').jr('.stop', 'z')
a.ld_abs_a(gapcount)
a.lab('.gaploop')
a.call('delay_one_bit')
a.ld_a_abs(sticky).and_(K_START | K_B).jr('.stop', 'nz')
a.ld_a_abs(gapcount).dec('a').ld_abs_a(gapcount).jr('.gaploop', 'nz')
a.jr('.burst')
a.lab('.stop').call('motor_off').ret()

a.lab('run_on_sweep')
a.ld('a', 1).ld_abs_a(sweepn)
a.lab('.step')
a.call('draw_all')
a.xor('a').ld_abs_a(sticky)
a.ld('a', 4).ld_abs_a(tmpB2)
a.lab('.rep')
a.call('prespin_do')
a.call('sync_fr')
a.call('motor_on')
a.ld_a_abs(sweepn).call('delay_bits')
a.call('motor_off')
for _ in range(4):
    a.ld('a', 250).call('delay_ms')
    a.ld_a_abs(sticky).and_(K_START | K_B).jp('.quit', 'nz')
a.call('readkeys')
a.ld_a_abs(tmpB2).dec('a').ld_abs_a(tmpB2).jr('.rep', 'nz')
a.ld_a_abs(sticky)
a.bit(0, 'a').jr('.felt', 'nz')
a.and_(K_START | K_B).jr('.quit', 'nz')
a.ld_a_abs(sweepn).inc('a').cp(33).jr('.ok', 'c').ld('a', 1)
a.lab('.ok').ld_abs_a(sweepn)
a.jr('.step')
a.lab('.felt').ld_a_abs(sweepn).ld_abs_a(result)
a.lab('.quit').call('motor_off').ret()

a.lab('run_off_sweep')
a.ld('a', 1).ld_abs_a(sweepn)
a.lab('.step')
a.call('draw_all')
a.xor('a').ld_abs_a(sticky)
a.ld('a', 8).ld_abs_a(tmpB2)
a.call('sync_fr')
a.lab('.cyc')
a.call('motor_on')
a.ld('a', 8).call('delay_bits')
a.call('motor_off')
a.ld_a_abs(sweepn).call('delay_bits')
a.call('readkeys')
a.ld_a_abs(sticky).and_(K_START | K_B).jp('.quit', 'nz')
a.ld_a_abs(tmpB2).dec('a').ld_abs_a(tmpB2).jr('.cyc', 'nz')
a.call('motor_off')
a.ld('a', 200).call('delay_ms')
a.ld_a_abs(sticky)
a.bit(0, 'a').jr('.felt', 'nz')
a.and_(K_START | K_B).jr('.quit', 'nz')
a.ld_a_abs(sweepn).inc('a').cp(33).jr('.ok', 'c').ld('a', 1)
a.lab('.ok').ld_abs_a(sweepn)
a.jr('.step')
a.lab('.felt').ld_a_abs(sweepn).ld_abs_a(result)
a.lab('.quit').call('motor_off').ret()

# ---- text -------------------------------------------------------------
a.lab('print')
a.b(0x1A)
a.or_('a').ret('z')
a.sub(0x20)
a.push('af')
a.lab('.w').ldh_a(rSTAT).and_(2).jr('.w', 'nz')
a.pop('af')
a.ldi_hl_a()
a.inc16('de')
a.jr('print')

a.lab('print_i')                      # HL = dest, DE = string, inverted tiles
a.b(0x1A)
a.or_('a').ret('z')
a.sub(0x20)
a.add(0x50)
a.call('vput')
a.inc16('de')
a.jr('print_i')

a.lab('print_d')                      # HL = dest, DE = string, dim tiles
a.b(0x1A)
a.or_('a').ret('z')
a.sub(0x20)
a.add(0x90)
a.call('vput')
a.inc16('de')
a.jr('print_d')

a.lab('printn4')
a.ld16('de', numbuf)
a.ld('b', 4)
a.lab('.l')
a.b(0x1A)
a.push('af')
a.lab('.w').ldh_a(rSTAT).and_(2).jr('.w', 'nz')
a.pop('af')
a.ldi_hl_a()
a.inc16('de')
a.dec('b').jr('.l', 'nz')
a.ret()

a.lab('num2buf')                      # HL = 0..9999
a.ld('c', 0)
a.ld16('de', 0xFC18)                  # -1000
a.lab('.k').add_hl('de').jr('.k2', 'nc').inc('c').jr('.k')
a.lab('.k2').ld16('de', 1000).add_hl('de')
a.ld('a', 'c').add(0x10).ld_abs_a(numbuf)
a.ld('c', 0)
a.ld16('de', 0xFF9C)                  # -100
a.lab('.h').add_hl('de').jr('.h2', 'nc').inc('c').jr('.h')
a.lab('.h2').ld16('de', 100).add_hl('de')
a.ld('a', 'c').add(0x10).ld_abs_a(numbuf + 1)
a.ld('c', 0)
a.ld16('de', 0xFFF6)                  # -10
a.lab('.t').add_hl('de').jr('.t2', 'nc').inc('c').jr('.t')
a.lab('.t2').ld16('de', 10).add_hl('de')
a.ld('a', 'c').add(0x10).ld_abs_a(numbuf + 2)
a.ld('a', 'l').add(0x10).ld_abs_a(numbuf + 3)
a.ld_a_abs(numbuf).cp(0x10).ret('nz')
a.xor('a').ld_abs_a(numbuf)
a.ld_a_abs(numbuf + 1).cp(0x10).ret('nz')
a.xor('a').ld_abs_a(numbuf + 1)
a.ld_a_abs(numbuf + 2).cp(0x10).ret('nz')
a.xor('a').ld_abs_a(numbuf + 2)
a.ret()

a.lab('fillrow')                      # HL = dest, B = count, A = tile
a.lab('.l').ldi_hl_a().dec('b').jr('.l', 'nz')
a.ret()

a.lab('sep')                          # HL = row start
a.ld('a', 0x46).ldi_hl_a()
a.ld('b', 18).ld('a', 0x40).call('fillrow')
a.ld('a', 0x47).ldi_hl_a()
a.ret()

a.lab('draw_frame')                   # LCD is off here, plain writes
a.b(0x21).b(0x00, 0x98)
a.ld('a', 0x42).ldi_hl_a()
a.ld('b', 18).ld('a', 0x4C).call('fillrow')   # capped rule above the title
a.ld('a', 0x43).ldi_hl_a()
v = 0x9800 + 32
a.b(0x21).b(v & 0xFF, v >> 8)
a.ld('c', 16)
a.lab('.s')
a.ld('a', 0x41).b(0x77)               # ld [hl],a
a.push('hl')
a.ld16('de', 19).add_hl('de')
a.ld('a', 0x41).b(0x77)
a.pop('hl')
a.ld16('de', 32).add_hl('de')
a.dec('c').jr('.s', 'nz')
v = 0x9800 + 17 * 32
a.b(0x21).b(v & 0xFF, v >> 8)
a.ld('a', 0x44).ldi_hl_a()
a.ld('b', 18).ld('a', 0x40).call('fillrow')
a.ld('a', 0x45).ldi_hl_a()
for ry in (2, 6, 11):
    v = 0x9800 + ry * 32
    a.b(0x21).b(v & 0xFF, v >> 8)
    a.call('sep')
a.ret()

a.lab('vput')
a.push('af')
a.lab('.w').ldh_a(rSTAT).and_(2).jr('.w', 'nz')
a.pop('af')
a.ldi_hl_a()
a.ret()

a.lab('hexnib')
a.cp(10).jr('.d', 'c')
a.add(0x17)
a.jr('.w')
a.lab('.d').add(0x10)
a.lab('.w').call('vput').ret()

a.lab('draw_hex')                     # HL = dest, writes "$xx"
a.ld('a', 0x04)
a.call('vput')
a.ld_a_abs(pattern)
a.swap('a').and_(0x0F).call('hexnib')
a.ld_a_abs(pattern)
a.and_(0x0F).call('hexnib')
a.ret()

a.lab('draw_bits')
a.ld_a_abs(pattern).ld('c', 'a')
a.ld('b', 0)
a.lab('.l')
a.ld('a', 'c').b(0x0F).ld('c', 'a')
a.ld('a', 0x10)
a.jr('.z', 'nc')
a.ld('a', 0x11)
a.lab('.z')
a.ld('d', 'a')
a.ld_a_abs(cursor).cp('b').jr('.n', 'nz')
a.ld('a', 'd').add(0x50).ld('d', 'a')
a.lab('.n')
a.ld('a', 'd').call('vput')
a.inc('b')
a.ld('a', 'b').cp(8).jr('.l', 'c')
a.ret()

a.lab('draw_wave')                    # HL = dest, 8 square-wave cells
a.ld_a_abs(pattern).rlca().and_(1).ld('d', 'a')   # previous level = bit 7
a.ld_a_abs(pattern).ld('c', 'a')
a.ld('b', 8)
a.lab('.l')
a.ld('a', 'c').b(0x0F).ld('c', 'a')
a.ld('a', 0)
a.jr('.have', 'nc')
a.inc('a')
a.lab('.have')
a.ld('e', 'a')
a.cp('d').jr('.edge', 'nz')
a.ld('a', 'e').or_('a').jr('.low', 'z')
a.ld('a', 0x48).jr('.w')
a.lab('.low').ld('a', 0x49).jr('.w')
a.lab('.edge')
a.ld('a', 'e').or_('a').jr('.fall', 'z')
a.ld('a', 0x4A).jr('.w')
a.lab('.fall').ld('a', 0x4B)
a.lab('.w')
a.call('vput')
a.ld('a', 'e').ld('d', 'a')
a.dec('b').jr('.l', 'nz')
a.ret()

# ---- screen -----------------------------------------------------------
a.lab('draw_all')
ldhl(1, 1)
a.ld16('de', 's_title')
a.call('print_i')

pstr(1, 3, 's_mode')
a.ld_a_abs(mode).or_('a').jr('.m1', 'nz')
a.ld16('de', 's_m0').jr('.mw')
a.lab('.m1').cp(1).jr('.m2', 'nz')
a.ld16('de', 's_m1').jr('.mw')
a.lab('.m2').cp(2).jr('.m3', 'nz')
a.ld16('de', 's_m2').jr('.mw')
a.lab('.m3').ld16('de', 's_m3')
a.lab('.mw')
ldhl(8, 3)
a.ld_a_abs(running).or_('a').jr('.mn', 'z')
a.call('print_i')
a.jr('.md')
a.lab('.mn').call('print')
a.lab('.md')

# rows 4 and 5 swap between the pattern editor and the sweep readout
pstr(1, 4, 's_c18')
pstr(1, 5, 's_c18')
a.ld_a_abs(mode).or_('a').jr('.notpat', 'nz')
ldhl(2, 4)
a.call('draw_bits')
ldhl(12, 4)
a.call('draw_hex')
ldhl(2, 5)
a.call('draw_wave')
a.jp('.cont')
a.lab('.notpat')
a.cp(3).jr('.notpre', 'nz')
ldhl(2, 4)                            # PRESET: bits + hex, name below
a.call('draw_bits')
ldhl(12, 4)
a.call('draw_hex')
a.call('preset_addr')
a.ld16('de', 3).add_hl('de')
a.ld('d', 'h').ld('e', 'l')
ldhl(1, 5)
a.call('print')
a.jp('.cont')
a.lab('.notpre')
a.cp(1).jr('.s2', 'nz')
a.ld16('de', 's_onbits').jr('.sw')
a.lab('.s2').ld16('de', 's_offbits')
a.lab('.sw')
ldhl(1, 4)
a.call('print')
a.ld_a_abs(sweepn).ld('l', 'a').ld('h', 0).call('num2buf')
pnum(11, 4)
pstr(1, 5, 's_felt')
a.ld_a_abs(result).ld('l', 'a').ld('h', 0).call('num2buf')
pnum(9, 5)
pstr(14, 5, 's_bits')

a.lab('.cont')
pstr(1, 7, 's_bit')
a.ld_a_abs(unit).or_('a').jr('.ums', 'nz')
a.ld_a_abs(blen_fr).ld('l', 'a').ld('h', 0).call('num2buf')
pnum(5, 7)
pstr(10, 7, 's_fr')
a.call('get_bitms')
a.call('num2buf')
pnum(12, 7)
pstr(17, 7, 's_ms')
a.jr('.udone')
a.lab('.ums')
a.ld_a_abs(blen_ms).ld('l', 'a').ld('h', 0).call('num2buf')
pnum(5, 7)
pstr(10, 7, 's_ms')
pstr(13, 7, 's_6sp')
a.lab('.udone')

a.call('burst_ok').jr('.d1', 'z')
a.ld16('de', 's_cycle').jr('.dw')
a.lab('.d1').ld_a_abs(mode).cp(2).jr('.d2', 'nz')
a.ld16('de', 's_rest').jr('.dw')
a.lab('.d2').ld16('de', 's_pulse')
a.lab('.dw')
ldhl(1, 8)
a.call('print')
a.call('get_bitms')
a.call('burst_ok').jr('.n1', 'z')
a.ld('a', 8).jr('.nm')
a.lab('.n1').ld_a_abs(sweepn)
a.lab('.nm')
a.call('mul_hl_a')
a.call('num2buf')
pnum(8, 8)
pstr(13, 8, 's_ms')

pstr(1, 9, 's_prespin')
a.ld_a_abs(prespin).or_('a').jr('.po', 'z')
a.ld16('de', 's_on').jr('.pw')
a.lab('.po').ld16('de', 's_off')
a.lab('.pw')
ldhl(10, 9)
a.call('print')

a.call('burst_ok').jr('.dblank', 'z')
pstr(1, 10, 's_runlbl')
a.ld_a_abs(duration).or_('a').jr('.dcont', 'z')
a.ld('l', 'a').ld('h', 0).call('num2buf')
pnum(4, 10)
pstr(9, 10, 's_gap')
a.ld_a_abs(gap).ld('l', 'a').ld('h', 0).call('num2buf')
pnum(13, 10)
a.jr('.dend')
a.lab('.dcont')
pstr(5, 10, 's_contv')
a.jr('.dend')
a.lab('.dblank')
pstr(1, 10, 's_c18')
a.lab('.dend')

pdim(1, 12, 's_h1')
a.ld_a_abs(mode).or_('a').jr('.ha1', 'nz')
a.ld16('de', 's_aflip').jr('.hw')
a.lab('.ha1').cp(3).jr('.ha2', 'nz')
a.ld16('de', 's_ause').jr('.hw')
a.lab('.ha2').ld16('de', 's_afelt')
a.lab('.hw')
ldhl(1, 13)
a.call('print_d')
pdim(13, 13, 's_bmode')
pdim(1, 14, 's_h3')
pdim(1, 15, 's_h4')
a.call('burst_ok').jr('.h5s', 'z')
a.ld16('de', 's_h5').jr('.h5w')
a.lab('.h5s').ld16('de', 's_c18')
a.lab('.h5w')
ldhl(1, 16)
a.call('print_d')
a.ret()

# ---- data -------------------------------------------------------------
strings = {
    's_title': " RUMBLE PULSE TEST",
    's_mode': "MODE",
    's_m0': "PATTERN  ",
    's_m1': "ON SWEEP ",
    's_m2': "OFF SWEEP",
    's_m3': "PRESET   ",
    's_ause': "A=USE IT   ",
    's_onbits': "ON BITS  ",
    's_offbits': "OFF BITS ",
    's_bit': "BIT",
    's_cycle': "CYCLE",
    's_pulse': "PULSE",
    's_rest': "REST ",
    's_ms': "MS",
    's_fr': "FR",
    's_prespin': "PRESPIN",
    's_on': "ON ",
    's_off': "OFF",
    's_runlbl': "RUN",
    's_contv': "CONT           ",
    's_gap': "GAP",
    's_felt': "FELT AT",
    's_bits': "BITS",
    's_5sp': "     ",
    's_7sp': "       ",
    's_8sp': "        ",
    's_h1': "START=RUN/STOP",
    's_aflip': "A=FLIP BIT  ",
    's_afelt': "A=I FEEL IT ",
    's_bmode': "B=MODE",
    's_h3': "UD=LEN    LR=MOVE",
    's_h4': "SEL+A=UNIT +B=SPIN",
    's_h5': "SEL+UD=RUN +LR=GAP",
    's_c18': "                  ",
    's_6sp': "      ",
}
for k, v in strings.items():
    a.lab(k)
    a.ascii(v)

a.lab('presets')
a.b(0x05, 8, 16)
a.ascii('WALL HIT    ')
a.b(0xFF, 3, 0)
a.ascii('BUMPER      ')
a.b(0x33, 8, 0)
a.ascii('GENGAR BONUS')
a.b(0x11, 8, 0)
a.ascii('SLOW TICK   ')
a.b(0x01, 8, 0)
a.ascii('SPARSE TICK ')
a.b(0x55, 64, 0)
a.ascii('OPTION DEMO ')
a.b(0xFF, 96, 0)
a.ascii('PIKA SAVE   ')
a.b(0xFF, 1, 0)
a.ascii('SHORT BLIP  ')
a.b(0xFF, 0, 0)
a.ascii('SOLID REF   ')
a.b(0x0F, 0, 0)
a.ascii('HALF DUTY   ')

a.lab('fontdata')
for byte in font.all_tiles():
    a.b(byte)

code_end = a.pc
a.resolve()

x = 0
for i in range(0x134, 0x14D):
    x = (x - a.rom[i] - 1) & 0xFF
a.rom[0x14D] = x
g = 0
for i in range(len(a.rom)):
    if i not in (0x14E, 0x14F):
        g = (g + a.rom[i]) & 0xFFFF
a.rom[0x14E] = (g >> 8) & 0xFF
a.rom[0x14F] = g & 0xFF

# test.py and render.py import this for a.rom and a.labels, so assembling has
# to happen at import. Writing the file does not: guarding it keeps them from
# overwriting the checked-in ROM as a side effect of running.
if __name__ == '__main__':
    with open(ROM_PATH, 'wb') as f:
        f.write(a.rom)
    print("code ends at 0x%04X (%d bytes of 0x8000)" % (code_end, code_end))
    print("header checksum 0x%02X" % x)
