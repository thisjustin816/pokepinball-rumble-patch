"""Boot the ROM headless, drive the buttons, and assert the rumble timings.

Replays two of Pokemon Pinball's own events through the emulator and checks
the waveform on the rumble register against what the hardware would see, so a
change to a delay path fails here rather than on a flashed cartridge.
"""

import build
from emu import GB

CYCLES_PER_SECOND = 4194304.0
FRAME_MS = 16.742

# What the waveform should measure. Stated once so a change lands in the
# assertion and its message together.
WALL_REST_MS = 368.2
BUMPER_PULSE_MS = 50.3
# A sweep checks for A between 50 ms slices of its gap.
FELT_ANSWER_MS = 100

# WRAM offsets from 0xC000, matching build.py.
PATTERN, CURSOR, MODE, RESULT_ON = 0x00, 0x01, 0x03, 0x06
RUNNING, DURATION, GAP, RESULT_OFF = 0x11, 0x1A, 0x1C, 0x1F

# The tile map cell under the last digit of FELT AT, row 5 column 12.
FELT_AT_CELL = 0x1800 + 5 * 32 + 12

gb = GB(build.a.rom)
labels = build.a.labels


def until(pc, limit=80_000_000):
    """Step until the program counter reaches pc. False if it never does."""
    steps = 0
    while gb.pc != pc and steps < limit:
        gb.step()
        steps += 1
    return gb.pc == pc


def run(cycles):
    end = gb.cyc + cycles
    while gb.cyc < end:
        gb.step()


def tap(key, hold=200_000, after=250_000):
    gb.keys = key
    run(hold)
    gb.keys = 0
    run(after)


def hold_select(key, address, value, max_seconds=20):
    """Hold SELECT plus key until the WRAM byte at address reaches value."""
    start = gb.cyc
    while gb.wram[address] != value and gb.cyc - start < int(CYCLES_PER_SECOND * max_seconds):
        gb.keys = 0x04 | key
        run(60_000)
    gb.keys = 0
    run(300_000)


def set_cursor(column):
    while gb.wram[CURSOR] != column:
        tap(0x10)


def segments():
    """The rumble log as alternating (on, milliseconds) pairs."""
    log = gb.log
    return [
        (bool(log[i][1]), (log[i + 1][0] - log[i][0]) / CYCLES_PER_SECOND * 1000)
        for i in range(len(log) - 1)
    ]


def close_to(measured, expected, tolerance=0.5):
    return abs(measured - expected) <= tolerance


assert until(labels['main']), "ROM never reached its main loop"

# The game's wall hit: pattern $05, an 8-bit burst, then a rest. $55 becomes
# $05 by clearing bits 4 and 6.
set_cursor(4)
tap(0x01)
set_cursor(6)
tap(0x01)
assert gb.wram[PATTERN] == 0x05, "pattern is %02X, not 05" % gb.wram[PATTERN]

hold_select(0x80, DURATION, 8)
hold_select(0x10, GAP, 16)
assert gb.wram[DURATION] == 8, "RUN is %d, not 8" % gb.wram[DURATION]
assert gb.wram[GAP] == 16, "GAP is %d, not 16" % gb.wram[GAP]

gb.log.clear()
tap(0x08, 200_000, 100_000)
run(int(CYCLES_PER_SECOND * 2.0))
cadence = segments()
print("wall-hit cadence:")
for on, ms in cadence[:8]:
    print("   %s %7.1f ms" % ("ON " if on else "off", ms))

# $05 is 1 on, 1 off, 1 on, then 5 off; the 16-bit gap extends that last rest.
assert len(cadence) >= 8, "only %d transitions, expected the burst to repeat" % len(cadence)
assert cadence[0][0], "the burst did not start with the motor on"
for index, (on, ms) in enumerate(cadence[:3]):
    assert close_to(ms, FRAME_MS), "segment %d is %.1f ms, not one frame" % (index, ms)
assert close_to(cadence[3][1], WALL_REST_MS, 1.0), \
    "the rest is %.1f ms, not %.1f" % (cadence[3][1], WALL_REST_MS)
assert not cadence[3][0], "the rest has the motor on"

gb.keys = 0x08
run(300_000)
gb.keys = 0
run(400_000)
assert gb.rumble == 0, "the motor is still on after stopping"
print("stopped motor=%d" % gb.rumble)

# A bumper: $FF for 3 frames, which is one solid 50 ms pulse.
for bit in range(8):
    set_cursor(bit)
    if not (gb.wram[PATTERN] >> bit) & 1:
        tap(0x01)
assert gb.wram[PATTERN] == 0xFF, "pattern is %02X, not FF" % gb.wram[PATTERN]

hold_select(0x80, DURATION, 3)
hold_select(0x20, GAP, 0)
gb.log.clear()
tap(0x08, 200_000, 100_000)
run(int(CYCLES_PER_SECOND * 1.0))
bumper = segments()
assert len(gb.log) == 2, "%d transitions, expected one pulse" % len(gb.log)
assert bumper[0][0], "the bumper pulse did not start with the motor on"
assert close_to(bumper[0][1], BUMPER_PULSE_MS), \
    "the bumper pulse is %.1f ms, not %.1f" % (bumper[0][1], BUMPER_PULSE_MS)
print("bumper: %d transitions, on %.1f ms" % (len(gb.log), bumper[0][1]))

# ON SWEEP: A in the first step's gap records step 1 and ends the run.
tap(0x02)
assert gb.wram[MODE] == 1, "B did not switch to ON SWEEP"
tap(0x08, 200_000, 100_000)
run(int(CYCLES_PER_SECOND * 1.5))
assert gb.wram[RUNNING], "ON SWEEP stopped before A was pressed"
start = gb.cyc
gb.keys = 0x01
while gb.wram[RUNNING] and gb.cyc - start < int(CYCLES_PER_SECOND * 5):
    gb.step()
gb.keys = 0
answer_ms = (gb.cyc - start) / CYCLES_PER_SECOND * 1000
assert answer_ms <= FELT_ANSWER_MS, \
    "ON SWEEP took %.0f ms to answer A, not under %d" % (answer_ms, FELT_ANSWER_MS)
assert gb.wram[RESULT_ON] == 1, "FELT AT is %d, not step 1" % gb.wram[RESULT_ON]
run(400_000)
assert gb.vram[FELT_AT_CELL] == ord('1') - 0x20, "FELT AT does not show 1"
print("on sweep: A answered in %.0f ms, felt at step %d" % (answer_ms, gb.wram[RESULT_ON]))

# OFF SWEEP keeps its own reading, so it shows none yet.
tap(0x02)
assert gb.wram[MODE] == 2, "B did not switch to OFF SWEEP"
assert gb.wram[RESULT_OFF] == 0, "OFF SWEEP starts with a reading of %d" % gb.wram[RESULT_OFF]
assert gb.vram[FELT_AT_CELL] == ord('-') - 0x20, "OFF SWEEP shows a reading it never took"
print("off sweep: no reading shown")

print("all timings within tolerance")
