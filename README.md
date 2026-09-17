# pokepinball-rumble-patch

Pokemon Pinball barely rumbles on some flashcarts. This patches a ROM so it
does. Verified on the original game and on Pokemon Pinball Generations 1.6.
Generations 1.1 through 1.5 and other hacks should work too, since sites are
matched by instruction shape rather than offset, as long as they leave the
rumble code alone. Apply this last, after any other patch.

```powershell
./Set-PinballRumble.ps1 -Rom pokepinball.gbc -Preset GBMake
```

Writes `pokepinball [rumble fix (s3) by thisjustin816].gbc` and never touches
the input. Needs PowerShell 7.

Windows marks anything extracted from a downloaded zip, and the default
execution policy refuses to run a marked script. Cloning the repository avoids
the mark; after extracting a zip, `Unblock-File ./Set-PinballRumble.ps1` clears
it.

> The code, test ROM, and documentation were written with AI assistance
> (Claude).

## Which cartridges need it

Switch rumble on in the options screen. The game answers with about a second of
single-frame ticks.

- **Rumble:** the motor starts on a single frame. Not needed.
- **Nothing:** the motor cannot start that fast, and most of the game is silent
  for the same reason.

Flipper hits are separate. A collision only rumbles if the ball is already
moving fast, so swinging a flipper into a slow ball does nothing, even on an
original cartridge. `-CollisionThreshold` sets that speed. The game ships 3, and
lowering it rumbles on more hits. It combines with any preset, for the reason
under [Velocity gates](#velocity-gates):

```powershell
./Set-PinballRumble.ps1 -Rom pokepinball.gbc -Preset GBMake -CollisionThreshold 2
```

## Why

**Every hard collision, flippers included, rumbles for a single frame: 17 ms.**
That is the most frequent rumble in the game and the whole problem. An original
cartridge's motor answers a 17 ms pulse, and the schedule was written for it.
Some flashcart motors need tens of milliseconds to reach speed, so they never
start.

Each event writes two bytes: a pattern and a duration. The pattern is rotated
one bit per frame and bit 0 drives the motor, so it is an 8-frame schedule that
repeats until the duration runs out. A frame is 17 ms. Every rumble site in
Generations 1.6, matched to the routine that writes it:

| Event                             | Pattern | Duration | Motor            | Sites | Lockout |
| --------------------------------- | ------- | -------- | ---------------- | ----- | ------- |
| Hard collision, flippers included | `$FF`   | 1 fr     | **solid, 17 ms** | 1     |         |
| Bumpers, Voltorb, Shellder        | `$FF`   | 3 fr     | solid, 51 ms     | 15    |         |
| Pikachu saver kick                | `$FF`   | 96 fr    | solid, 1.6 s     | 6     |         |
| Diglett, Psyduck, Poliwag scoring | `$55`   | 4 fr     | 17 ms twice      | 6     |         |
| Options-screen rumble toggle      | `$55`   | 64 fr    | 17 ms, 32 times  | 1     |         |
| Wall hits, in the stage files     | `$05`   | 8 fr     | 17 ms twice      | 19    | yes     |
| Slots, Ditto slots, force fields  | `$05`   | 8 fr     | 17 ms twice      | 12    |         |
| `Func_18464` and four like it     | `$33`   | 8 fr     | 34 ms twice      | 5     |         |
| `Func_18876`                      | `$11`   | 8 fr     | 17 ms twice      | 1     |         |
| `Func_188e1`                      | `$01`   | 8 fr     | 17 ms once       | 1     |         |

Sixty-seven sites, six of most things because each playfield carries its own
copy. The names come from the
[pokepinball-generations](https://github.com/huderlem/pokepinball-generations)
source; the five `$33` sites and two others are still unnamed there.

The wall hits are the only family with a lockout, so they get their own row
despite sharing a pattern and a duration with the slots. Each reads
`wRumbleDuration` first and returns early when it is non-zero, so a hit landing
inside a running burst is dropped rather than queued.

Two things go wrong on a slow motor, and they take different fixes.

**Short events.** Collisions, bumpers and the saver kick use an all-ones
pattern, so the motor is driven every frame of their duration. Only the length
is wrong, and a collision's length is one frame.

**Pulsing events.** The options toggle, the slots and the scoring events use
sparse patterns like `$55`, one frame on and one off for as long as the event
runs. Duration cannot fix that: a longer event is more 17 ms pulses, not wider
ones. The pattern byte has to change.

`-StartFrames` fixes both. It takes the number of frames the motor needs to
start from rest and rewrites every pulse to at least that long. Solid events
have no pulse to widen, so their duration is raised to `ceil(1.5 x StartFrames)`
instead, unless they already run that long or eight frames and up, which is
well past the threshold already.

A pulse behind a one-frame gap keeps its original length, because the motor
never stopped, so the rhythm survives the rewrite:

```text
$01  10000000  ->  $07  11100000      one kick, long enough to start
$05  10100000  ->  $17  11101000      strong tap, then a light one
$11  10001000  ->  $77  11101110      two kicks, both from rest
$33  11001100  ->  $77  11101110
$55  10101010  ->  $57  11101010      strong first, then the texture
$FF  11111111  ->  unchanged, duration raised instead
```

## Presets

| Preset          | What it is                                           |
| --------------- | ---------------------------------------------------- |
| `Original`      | the values the game ships. The default               |
| `GBMake`        | measured with `rumble-pulse.gb`, start 3 frames      |
| `AliExpress`    | the 64Mbit Shock Flash Card, which rumbles unpatched |
| `InsideGadgets` | TBD                                                  |

`Original` and `AliExpress` change nothing, since those motors already feel the
single-frame pulses. InsideGadgets has not been measured, so that preset refuses
rather than guessing.

The `GBMake` board is a ChisFlash MBCX, but the rumble option is GBMake's: the
ChisFlash store sells that mapper without a motor.

`-Preset Original` also writes the shipped values back, recovering most of a
patched ROM: the gate, both velocity gates and the collision duration.

It is a repair rather than a round trip. Two kinds of byte cannot come back,
because nothing records what they were. Rescaling maps several patterns onto
one, so a `$77` could have been `$11` or `$33`. Durations raised by a start
length are not recorded either, so the 15 bumper events stay raised. Patching
`pokepinball.gbc` with `-Preset GBMake` changes 61 bytes and `-Preset Original`
puts back 1 of them. Keep the unpatched ROM.

## Calibrating a board

Motors differ between cartridges, so one board's numbers won't apply to others.
[`rumble-pulse/`](rumble-pulse/) holds a 32 KiB test ROM that plays
arbitrary patterns on demand. Flash it, keep `BIT` at `1 FR`, and take one
reading per mode:

| Measure    | Mode      | PRESPIN | Record                                   | Parameter        |
| ---------- | --------- | ------- | ---------------------------------------- | ---------------- |
| cold start | ON SWEEP  | off     | first step that registers                | `-StartFrames`   |
| sustain    | ON SWEEP  | on      | first step while already turning         | `-SustainFrames` |
| coast      | OFF SWEEP | n/a     | longest rest that still feels continuous | `-CoastGap`      |

Then patch with what came back:

```powershell
./Set-PinballRumble.ps1 -Rom pokepinball.gbc -StartFrames 3 -SustainFrames 1 -CoastGap 1
```

Sanity check first: `PATTERN $FF`, `RUN 6`, `GAP 0`. If that is not
unmistakable, the cartridge is underdriven and no patch will rescue it.

Record coast conservatively. If a one-frame gap already reads as pulsing rather
than solid, `-CoastGap` is 1; setting it to 0 treats every pulse as a cold start.

A GBMake board measures **3, 1, 1**. Keep sustain low: raising it collapses the
difference between a pulse from rest and one behind a short gap, and at
`-SustainFrames 3` with `-StartFrames 3` every pattern rescales to the same byte.

### When no start length is enough

`-StartFrames` stops at 7, because a pattern is an 8-frame loop and an 8-frame
pulse leaves no room for the gap that makes it a pulse. A motor still not
answering at 7 wants `-HoldGate`, which changes VBlank's `and $1` to `and $ff`
so the motor runs for each event's whole duration rather than only the frames
its pattern sets.

That reaches a motor no pattern can, and costs the game its rumble texture:
every event feels the same. It is opt in for that reason, and combines with
neither a start length nor a preset, both of which it would make meaningless.

### Reading the output name

Each run names its output for the bytes it wrote, in the bracketed form
GoodTools and TOSEC use for an unofficial change, so a session of several
settings leaves one file each to compare rather than one overwritten:

```text
pokepinball [rumble fix (s3) by thisjustin816].gbc
pokepinball [rumble fix (s4) by thisjustin816].gbc
pokepinball [rumble fix (t2w1-s4) by thisjustin816].gbc
```

| Letter | Byte it wrote                               |
| ------ | ------------------------------------------- |
| `s3`   | start length, so every pattern was rescaled |
| `f1`   | collision duration in frames                |
| `t3`   | collision velocity gate                     |
| `w2`   | wall velocity gate                          |
| `g`    | the gate held on                            |

A letter appears only when that byte was written, so `(s3)` touched no gate and
no duration of its own, and `(f1t2w2)` is `-Preset Original` putting the shipped
values back with one threshold changed. `-Author` changes the credit, and
`-Author ''` drops it.

### Checking a patch before flashing

Any pair the patch produces can be replayed in the test ROM. Set `PATTERN` to
the byte, `RUN` to the duration, `GAP` to the frames between repeats:

| Check                         | PATTERN | RUN | GAP |
| ----------------------------- | ------- | --- | --- |
| wall hit as shipped           | `$05`   | 8   | 16  |
| wall hit as patched           | `$17`   | 8   | 16  |
| bumper as shipped             | `$FF`   | 3   | 0   |
| bumper as patched             | `$FF`   | 5   | 0   |
| fast volley at patched values | `$17`   | 8   | 2   |

The last row catches mistakes: it is the patched wall hit at the fastest rate
the lockout permits, and if it smears into one continuous buzz the events are
too long for the hit rate.

Duration is doing three jobs at once, and that is what makes the check worth
running. It sets how long an event plays, it sets intensity because a motor
still ramping keeps getting stronger, and it caps the event rate at
`60 / duration` per second through the lockout below. Spend length on one-shots
like the saver kick, not on events that fire in clusters.

## Velocity gates

Whether an event fires at all is separate from how long it runs. Only two of
the families above gate on the ball's speed, and they ship different values:

| Site                                       | Gate   | Count | Sets it               |
| ------------------------------------------ | ------ | ----- | --------------------- |
| `ApplyCollisionForces`, the hard collision | `cp 3` | 1     | `-CollisionThreshold` |
| the wall hits                              | `cp 2` | 19    | `-WallThreshold`      |

No motor preset touches either, and both are left as the game ships them unless
asked for, because they are game logic rather than motor compensation and are
identical on an original cartridge. That is also why they combine with a preset
instead of competing with it. Lowering the wall gate admits slower contact, but
the lockout drops the surplus unless the events get shorter too.

## Notes

`Get-Help ./Set-PinballRumble.ps1 -Full` documents every parameter.

Sites are found by instruction shape with the WRAM address read out of the
match, so a build whose WRAM sits elsewhere still patches. Anything it cannot
find uniquely, it refuses to guess at.

Run it from a [pret/pokepinball](https://github.com/pret/pokepinball) or
[pokepinball-generations](https://github.com/huderlem/pokepinball-generations)
checkout and `-Rom` defaults to whatever that Makefile builds. `-Makefile` takes
a path to one and does the same from anywhere.

`Invoke-Pester ./tests` runs the script end to end against synthetic ROMs, and
`Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
is the style check. GitHub Actions runs both on every push, along with a rebuild
of the test ROM that fails if the checked-in copy has drifted from its source.

## Credit

Came out of chasing weak rumble on a GBMake cartridge, reported as
[pokepinball-generations#15](https://github.com/huderlem/pokepinball-generations/issues/15).
