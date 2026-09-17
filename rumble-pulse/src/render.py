"""Render the emulated tile map to PNG, for checking layout without hardware.

Boots the ROM, walks to each mode, and writes a screenshot straight out of
VRAM, so the images in the README cannot drift from what the ROM draws.
"""

import os

import build
from emu import GB
from PIL import Image

SCALE = 3
# The DMG palette, darkest last.
PALETTE = [(224, 248, 208), (136, 192, 112), (52, 104, 86), (8, 24, 32)]

gb = GB(build.a.rom)
labels = build.a.labels


def until(pc, limit=60_000_000):
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


def shot(name):
    """Write the current tile map to screenshots/<name>."""
    image = Image.new('RGB', (160, 144))
    pixels = image.load()
    for tile_y in range(18):
        for tile_x in range(20):
            tile = gb.vram[0x1800 + tile_y * 32 + tile_x]
            base = tile * 16
            for row in range(8):
                low = gb.vram[base + row * 2]
                high = gb.vram[base + row * 2 + 1]
                for column in range(8):
                    bit = 7 - column
                    shade = ((low >> bit) & 1) | (((high >> bit) & 1) << 1)
                    pixels[tile_x * 8 + column, tile_y * 8 + row] = PALETTE[shade]
    image = image.resize((160 * SCALE, 144 * SCALE), Image.NEAREST)
    path = os.path.join(build.SHOT_DIR, name)
    image.save(path)
    print("wrote", path)


os.makedirs(build.SHOT_DIR, exist_ok=True)
assert until(labels['main']), "ROM never reached its main loop"
shot('shot_pattern.png')
# One sweep stands for both: OFF SWEEP differs only in its two labels.
tap(0x02)
shot('shot_onsweep.png')
