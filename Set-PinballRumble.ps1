#Requires -Version 7.0

<#
.SYNOPSIS
Rescales Pokemon Pinball's rumble patterns and durations for a board whose
motor does not start within one frame.

.DESCRIPTION
Each rumble event writes a pattern byte and a duration. The pattern is
rotated one bit per frame with bit 0 driving the motor, so it is an 8-frame
schedule that repeats. Most of the game is single-frame pulses, which a
slow motor never answers. README.md has the detail.

Sites are found by instruction shape with the WRAM address read out of the
match, so a build whose WRAM sits elsewhere patches too. Each is refused
unless its pattern occurs exactly once, so this either patches the site it
identified or leaves the file alone. Four kinds of site:

- Every sparse pattern, rescaled by -StartFrames so each pulse is long
  enough for the motor to answer. This is the one to reach for.
- VBlank's rumble gate (home.asm), where `and $1` tests the bit that
  landed in position 0 this frame. Changed to `and $ff` the motor stays on
  while any bit remains set, which drives solidly for the whole duration.
  -HoldGate asks for it; it reaches a motor no pattern can, and costs the
  game its rumble texture.
- ApplyCollisionForces, the rumble on every hard hit: -CollisionFrames sets
  its duration, -CollisionThreshold the velocity it demands.
- The wall handlers, whose own velocity gate -WallThreshold sets.

Motor settings come either from -Preset or by hand, not both. The two
velocity gates are game logic rather than motor compensation, so they are
outside that choice and combine with either.

.PARAMETER Rom
The ROM file to read. Not modified. Without it, -Makefile says where to
find one.

.PARAMETER Makefile
A pret/pokepinball or pokepinball-generations Makefile, whose ROM line
names what that checkout builds. The built file is looked for beside it.
Defaults to ./Makefile, so running this from a checkout needs neither
parameter. Cannot be combined with -Rom.

Nothing looks beside the script itself, so it can live anywhere instead
of being copied into the checkout.

.PARAMETER Preset
Which cartridge to tune for.

Original       the values the game ships
GBMake         measured with rumble-pulse.gb, start 3 frames
AliExpress     the 64Mbit Shock Flash Card, which rumbles unpatched
InsideGadgets  TBD

Original writes the shipped values rather than skipping, so it recovers
most of a patched ROM when the unpatched one is gone. It puts back the
gate, both velocity gates and the collision duration.

Two kinds of byte cannot come back, so this is a repair rather than a
round trip. Rescaling maps several patterns onto one, so a $77 could have
been $11 or $33 and there is no telling which. Durations raised by a start
length are not recorded either, so the 15 bumper events stay at their
raised length. Keep the unpatched ROM.

A preset without values refuses to guess. Measure the cartridge with
rumble-pulse.gb and report what suits it so the preset can carry it.

-Preset cannot be combined with the motor values below, since a preset is
a set of them. It does combine with -CollisionThreshold and -WallThreshold,
which are game logic that no motor preset owns, and an explicit value there
wins over the one -Preset Original restores.

.PARAMETER OutFile
Where to write the patched ROM. Refused if it resolves to the same file as
-Rom.

Without it the name carries the settings in the bracketed form GoodTools
and TOSEC use for an unofficial change, so pokepinball.gbc rescaled for a
start length of 3 becomes

    pokepinball [rumble fix (s3) by thisjustin816].gbc

and a session of several settings leaves one file each to compare.

.PARAMETER Author
Who the bracketed tag credits for the fix. Defaults to the author of this
script, since the fix is this script's rather than the caller's. Name
someone else to claim a variant, or pass an empty string to leave the tag
unattributed.

It becomes part of a filename, so \ / : * ? " < > | and control characters
are refused. That is the conservative set rather than this platform's, so a
name made on Linux still lands on a FAT flashcart.

.PARAMETER CollisionFrames
How many frames the hard-collision rumble lasts before scaling. The most
frequent rumble in play. The game ships 1.

.PARAMETER CollisionThreshold
How fast the ball must be arriving for a hard collision to rumble at all.
The game ships 3, and lowering it rumbles where an original cartridge stays
silent, so it is a matter of taste. Left untouched unless asked for, and
combines with -Preset; see the description above for why.

The test is on the ball's own incoming velocity, so a ball driven into a
flipper passes it while a flipper swung into a slow ball does not. The
lower it goes the closer this gets to rumbling continuously in play.

A ball resting against a flipper has no incoming velocity at all, so only
0 catches it, and 0 is also the setting most likely to buzz constantly.
Collisions where the ball is moving away are dropped before this test and
stay silent at any value.

.PARAMETER WallThreshold
How fast the ball must be arriving for a wall handler to rumble. The game
ships 2, already lower than ApplyCollisionForces at 3. Behaves like
-CollisionThreshold: no parameter set, combines with -Preset, untouched
unless asked for.

There are 19 of these against that one, and they carry a lockout the
collision site does not: each reads wRumbleDuration and returns early when
it is non-zero, so a hit landing inside a running burst is dropped rather
than queued. Lowering this admits slower contact, but the surplus is
dropped unless the durations come down with it, so lower it and shorten
the events together.

.PARAMETER StartFrames
How many frames the motor needs to register a pulse it starts from rest.
Measure it with rumble-pulse.gb: run ON SWEEP with PRESPIN off and record
the first step that registers.

Every sparse pattern is rewritten so its pulses are at least this long. A
pulse whose gap is short enough that the motor never stops needs only a
frame, so the rhythm survives rather than being flattened into solid
drive. Patterns that cannot fit in eight frames drop their last pulse.

7 is the most this can be, since a pattern is an 8-frame loop and an
8-frame pulse leaves no room for the gap that makes it a pulse. A motor
needing that long wants -HoldGate instead.

Solid patterns have no pulse to widen, so their duration is raised instead,
to ceil(1.5 * StartFrames), which is past the threshold rather than sitting
on it. Events already running eight frames or more are well past it and are
left alone, as is anything already at that length or longer.

It takes over the collision duration unless -CollisionFrames is given
explicitly, and cannot be combined with -HoldGate, which would make every
pattern solid and leave nothing to rescale.

.PARAMETER SustainFrames
How many frames the motor needs to register while it is already turning.
Measure it with rumble-pulse.gb: ON SWEEP with PRESPIN on. Defaults to 1.

This is what keeps a rhythm intact. Raising it moves the rescale toward
every pulse being a full start length, so at SustainFrames equal to
StartFrames there is no cold-start distinction left and every pattern
collapses to the same shape.

.PARAMETER CoastGap
The longest gap, in frames, that the motor coasts through without coming
to rest. Measure it with rumble-pulse.gb: OFF SWEEP. Defaults to 1.

A pulse behind a gap this long or shorter needs only SustainFrames; behind
a longer one it needs the full StartFrames. Setting it to 0 means every
pulse is treated as a cold start.

.PARAMETER HoldGate
Hold VBlank's rumble gate on, which drives the motor solidly for each
event's whole duration instead of only the frames its pattern sets.

The blunt alternative to -StartFrames: it reaches a motor that no pattern
can, at the cost of every event feeling the same, since a held gate makes
every pattern read as solid. Reach for it when a start length of 7 is still
not enough, and expect the game to lose its rumble texture. Cannot be
combined with -StartFrames or a toggle pattern, which it would render
meaningless, nor with -Preset, which carries its own gate value.

.PARAMETER SkipCollisionDuration
Do not write -CollisionFrames to ApplyCollisionForces. For testing the
changes apart.

Two things beside it are unaffected. The threshold is game logic and is
written whenever one was asked for. A start length still raises every solid
event under eight frames, this one among them, since that is the rescale
rather than this parameter.

.PARAMETER TogglePattern
Set the options-screen toggle to this pattern and change nothing else.

A probe rather than a setting, superseded by rumble-pulse.gb for most
purposes. The toggle is the one sparse event that needs no ball, no
collision and no velocity, and it runs for about a second, so it isolates
a pattern from everything else in the game. Cannot be combined with
-HoldGate, which would drive the probe pattern solidly.

.PARAMETER ToggleProbe
A named pattern for -TogglePattern, from a small set worth trying.

Stock   $55  1 on, 1 off, the pattern the game ships
Width2  $03  2 on, 6 off
Width3  $07  3 on, 5 off
Width4  $0F  4 on, 4 off
Gap1    $77  3 on, 1 off, twice
Mixed   $73  2 on, 2 off, 3 on, 1 off
Solid   $FF  always on, the control

.EXAMPLE
./Set-PinballRumble.ps1 -Rom PinballGenerations.gbc -Preset GBMake

Rescales every pattern for a motor that needs three frames to start.

.EXAMPLE
./Set-PinballRumble.ps1 -Rom PinballGenerations.gbc -Preset GBMake -CollisionThreshold 2

Rescales for that board and lowers the collision gate, so flippers swung
into a slow ball rumble too.

.EXAMPLE
./Set-PinballRumble.ps1 -Rom pokepinball.gbc -StartFrames 4

Rescales for a slower motor, measured rather than guessed.

.EXAMPLE
./Set-PinballRumble.ps1 -Rom pokepinball.gbc -CollisionThreshold 2

Changes one byte, so a cartridge that already rumbles also rumbles when a
flipper is swung into the ball.

.EXAMPLE
./Set-PinballRumble.ps1 -Rom patched.gbc -Preset Original -OutFile stock.gbc

Puts the gate, both velocity gates and the collision duration back to the
values the game ships, for a ROM whose unpatched original is gone. Rescaled
patterns and raised durations stay as they are; see -Preset.

.NOTES
This edits a file, not a cartridge. Flashing the result still means
erasing whatever is in the slot. The ROM checksum at 0x14E-0x14F is not
touched; the boot ROM does not check it.
#>
[CmdletBinding(DefaultParameterSetName = 'Preset')]
param (
    [string]$Rom,

    [string]$Makefile = (Join-Path $PWD 'Makefile'),

    [string]$OutFile,

    [ValidatePattern(
        '^[^\\/:*?"<>|\x00-\x1f]*$',
        ErrorMessage = (
            '-Author becomes part of a filename, so it cannot ' +
            'contain \ / : * ? " < > | or control characters.'
        )
    )]
    [string]$Author = 'thisjustin816',

    [Parameter(ParameterSetName = 'Preset')]
    [ValidateSet('Original', 'GBMake', 'InsideGadgets', 'AliExpress')]
    [string]$Preset = 'Original',

    [Parameter(ParameterSetName = 'Manual')]
    [ValidateRange(1, 255)]
    [int]$CollisionFrames = 1,

    [ValidateRange(0, 255)]
    [int]$CollisionThreshold = 3,

    [ValidateRange(0, 255)]
    [int]$WallThreshold,

    [Parameter(ParameterSetName = 'Manual')]
    [ValidateRange(1, 7)]
    [int]$StartFrames,

    [Parameter(ParameterSetName = 'Manual')]
    [ValidateRange(1, 8)]
    [int]$SustainFrames = 1,

    [Parameter(ParameterSetName = 'Manual')]
    [ValidateRange(0, 8)]
    [int]$CoastGap = 1,

    [byte]$TogglePattern,

    [ValidateSet('Stock', 'Width2', 'Width3', 'Width4', 'Gap1', 'Mixed', 'Solid')]
    [string]$ToggleProbe,

    [Parameter(ParameterSetName = 'Manual')]
    [switch]$HoldGate,

    [switch]$SkipCollisionDuration
)

begin {
    $ErrorActionPreference = 'Stop'

    # Patterns for the options-screen toggle, to find what a motor can feel. The
    # width ones keep a long gap so only the pulse is in question; Gap1 keeps the
    # pulses at the length the bumpers already prove, so only the gap is.
    $probes = @{
        Stock  = @{ Byte = 0x55; Note = '1 on, 1 off: the pattern the game ships' }
        Width2 = @{ Byte = 0x03; Note = '2 on, 6 off: 34 ms' }
        Width3 = @{ Byte = 0x07; Note = '3 on, 5 off: 51 ms, the length the bumpers prove' }
        Width4 = @{ Byte = 0x0F; Note = '4 on, 4 off: 68 ms' }
        Gap1   = @{ Byte = 0x77; Note = '3 on, 1 off, twice: does one frame of off stop the motor?' }
        Mixed  = @{ Byte = 0x73; Note = '2 on, 2 off, 3 on, 1 off: pulse and gap at once' }
        Solid  = @{ Byte = 0xFF; Note = 'always on: the control, which must be felt' }
    }

    # What each cartridge wants. Ones somebody has played carry values; the rest
    # say so rather than guessing, since a wrong guess here is a wasted flash.
    # GateValue is the operand of VBlank's "and": $ff holds the motor on for an
    # event's whole duration, $01 is what the game ships.
    $presets = @{
        Original      = @{
            Note               = 'the values the game ships'
            GateValue          = 0x01
            CollisionFrames    = 1
            CollisionThreshold = 3
            WallThreshold      = 2
        }
        GBMake        = @{
            # Measured with rumble-pulse.gb: 3 frames to break loose from rest, 1 to
            # register while already turning, and a 1-frame gap already reads as
            # pulsing. The thresholds are game logic and identical on an original
            # cartridge, so neither is touched.
            Note          = 'measured with rumble-pulse.gb on a GBMake rumble board'
            StartFrames   = 3
            SustainFrames = 1
            CoastGap      = 1
        }
        InsideGadgets = @{
            # insideGadgets build their rumble option around a "Pager Flat
            # Vibration Micro Motor DC 3V" and say their own Pokemon Pinball
            # example patch "doesn't appear to activate the rumble strong enough",
            # suggesting a lower resistor. That is this symptom, read as weak
            # drive. No values here yet, so the preset refuses
            # to guess.
            Note = 'TBD; the vendor reports the same weak rumble'
        }
        AliExpress    = @{
            # The "64Mbit Gb/gbc Shock Flash Card" sold there rumbles on the
            # unpatched game. Its listing advertises a Sanyo original motor, which
            # is the part the game's schedule was written against, so it starts
            # within a frame the way an original cartridge does. AliExpress is a
            # marketplace, not a board, so this speaks for that one alone; the
            # options-screen toggle in README.md is how to check another.
            Note               = 'the 64Mbit Shock Flash Card, whose Sanyo motor starts within a frame'
            GateValue          = 0x01
            CollisionFrames    = 1
            CollisionThreshold = 3
            WallThreshold      = 2
        }
    }

    <#
    .SYNOPSIS
    A pattern byte as the run lengths it plays, starting from rest.

    .DESCRIPTION
    Bit 0 plays first and the byte rotates, so the eight bits are a loop. This
    starts at the first set bit that follows a clear one, which is where the
    motor starts from a stop, and returns alternating on and off lengths from
    there. A byte that is all ones or all zeros has no such boundary and
    returns nothing.
    #>
    function Get-PatternRun {
        param ([int]$Pattern)
        $bits = 0..7 | ForEach-Object { ($Pattern -shr $_) -band 1 }
        $start = 0..7 | Where-Object { $bits[$_] -eq 1 -and $bits[($_ + 7) % 8] -eq 0 } | Select-Object -First 1
        # All ones or all zeros has no cold start, and emits nothing.
        if ($null -ne $start) {
            $runs = [System.Collections.Generic.List[object]]::new()
            $current = $bits[$start]
            $length = 0
            for ($i = 0; $i -lt 8; $i++) {
                $value = $bits[($start + $i) % 8]
                if ($value -eq $current) { $length++ }
                else {
                    $runs.Add([pscustomobject]@{ On = [bool]$current; Length = $length })
                    $current = $value
                    $length = 1
                }
            }
            $runs.Add([pscustomobject]@{ On = [bool]$current; Length = $length })
            $runs
        }
    }

    <#
    .SYNOPSIS
    A pattern rewritten so every pulse is long enough for the motor to answer.

    .DESCRIPTION
    Each on-run is lengthened to -StartFrames when the gap before it is long
    enough for the motor to stop, and to -SustainFrames when it is not, since a
    pulse behind a short gap rides on a motor that is still turning. Gaps keep
    the length they had, preserving the original rhythm, and the
    slack goes to the longest of them. A pattern that cannot fit in eight
    frames drops its last pulse and is tried again.
    #>
    function Get-RescaledPattern {
        param ([int]$Pattern, [int]$StartFrames, [int]$SustainFrames, [int]$CoastGap)
        $runs = @(Get-PatternRun -Pattern $Pattern)
        # A byte with no cold start, and one whose pulses cannot be made to fit,
        # both keep what they had. $needed staying empty is what says so.
        $value = $Pattern
        $needed = @()
        while ($runs.Count -gt 0) {
            $needed = [System.Collections.Generic.List[object]]::new()
            $gapBefore = 99
            foreach ($run in $runs) {
                if ($run.On) {
                    $floor = $gapBefore -le $CoastGap ? $SustainFrames : $StartFrames
                    $needed.Add([pscustomobject]@{ On = $true; Length = [math]::Max($run.Length, $floor) })
                }
                else {
                    $needed.Add([pscustomobject]@{ On = $false; Length = $run.Length })
                    $gapBefore = $run.Length
                }
            }
            $onTotal = ($needed | Where-Object On | Measure-Object -Property Length -Sum).Sum
            $gapCount = @($needed | Where-Object { -not $_.On }).Count
            if ($onTotal + $gapCount -le 8) { break }
            $lastOn = (0..($runs.Count - 1) | Where-Object { $runs[$_].On })[-1]
            # Indexes rather than Select-Object -Index, which throws on an empty set
            # instead of returning nothing, and dropping the only pulse empties it.
            $runs = @(
                0..($runs.Count - 1) |
                    Where-Object { $_ -ne $lastOn -and $_ -ne ($lastOn + 1) } |
                    ForEach-Object { $runs[$_] }
            )
            if (@($runs | Where-Object On).Count -eq 0) {
                $needed = @()
                break
            }
        }
        if ($needed.Count -gt 0) {
            $gapTotal = ($needed | Where-Object { -not $_.On } | Measure-Object -Property Length -Sum).Sum
            $slack = 8 - $onTotal - $gapTotal
            if ($slack -ne 0 -and $gapCount -gt 0) {
                $longest = $needed |
                    Where-Object { -not $_.On } |
                    Sort-Object Length -Descending |
                    Select-Object -First 1
                $longest.Length = [math]::Max(1, $longest.Length + $slack)
            }
            $value = 0
            $position = 0
            foreach ($run in $needed) {
                for ($i = 0; $i -lt $run.Length -and $position -lt 8; $i++) {
                    if ($run.On) { $value = $value -bor (1 -shl $position) }
                    $position++
                }
            }
        }
        $value
    }

    <#
    .SYNOPSIS
    Every offset in -Haystack where -Pattern occurs.

    .DESCRIPTION
    A -1 in -Pattern matches any byte, which is how the searches here
    leave a WRAM address open instead of assuming one.
    #>
    function Find-BytePattern {
        param ([byte[]]$Haystack, [int[]]$Pattern)
        $foundAt = [System.Collections.Generic.List[int]]::new()
        $last = $Haystack.Length - $Pattern.Length
        for ($i = 0; $i -le $last; $i++) {
            $isMatch = $true
            for ($j = 0; $j -lt $Pattern.Length; $j++) {
                if ($Pattern[$j] -ge 0 -and $Haystack[$i + $j] -ne $Pattern[$j]) {
                    $isMatch = $false
                    break
                }
            }
            if ($isMatch) { $foundAt.Add($i) }
        }
        $foundAt
    }

    <#
    .SYNOPSIS
    The offset of the only occurrence of a pattern, or a throw saying why not.
    #>
    function Get-SoleMatch {
        param ([byte[]]$Bytes, [int[]]$Pattern, [string]$Description)
        $offsets = Find-BytePattern -Haystack $Bytes -Pattern $Pattern
        if ($offsets.Count -eq 0) {
            throw "$Description`: pattern not found. This ROM may not build the source this expects."
        }
        if ($offsets.Count -gt 1) {
            throw (
                "$Description`: pattern found $($offsets.Count) times, not once. " +
                'Refusing to guess which is the real site.'
            )
        }
        $offsets[0]
    }

    <#
    .SYNOPSIS
    Report which rumble-handler shapes a ROM does contain.

    .DESCRIPTION
    Runs when the expected site is missing, so a failure says what the
    file holds instead of only that the search failed.
    #>
    function Show-WhatIsThere {
        param ([byte[]]$Bytes)
        # AddressAt is where the little-endian WRAM address starts within each
        # pattern, which is not the same place in all of them.
        $shapes = [ordered]@{
            'rotate, store, and $1 (unpatched)'   = @{
                Pattern = @(0x0F, 0xEA, -1, -1, 0xE6, 0x01, 0x28); AddressAt = 2
            }
            'rotate, store, and $ff (patched)'    = @{
                Pattern = @(0x0F, 0xEA, -1, -1, 0xE6, 0xFF, 0x28); AddressAt = 2
            }
            'rotate, store, any and'              = @{
                Pattern = @(0x0F, 0xEA, -1, -1, 0xE6); AddressAt = 2
            }
            'rotate then store, whatever follows' = @{
                Pattern = @(0x0F, 0xEA, -1, -1); AddressAt = 2
            }
            'ld a,$ff then store then ld a,n'     = @{
                Pattern = @(0x3E, 0xFF, 0xEA, -1, -1, 0x3E, -1, 0xEA, -1, -1); AddressAt = 3
            }
        }
        Write-Host ''
        Write-Host 'What this ROM does contain:' -ForegroundColor Cyan
        foreach ($label in $shapes.Keys) {
            $shape = $shapes[$label]
            $hits = Find-BytePattern -Haystack $Bytes -Pattern $shape.Pattern
            if ($hits.Count -eq 0) {
                Write-Host ('  {0,-38} none' -f $label)
                continue
            }
            $shown = $hits | Select-Object -First 4 | ForEach-Object {
                $at = $_ + $shape.AddressAt
                $wram = '${0:X2}{1:X2}' -f $Bytes[$at + 1], $Bytes[$at]
                '0x{0:X6} wram={1}' -f $_, $wram
            }
            $extra = $hits.Count -gt 4 ? " (+$($hits.Count - 4) more)" : ''
            Write-Host ('  {0,-38} {1}{2}' -f $label, ($shown -join ', '), $extra)
        }
        Write-Host ''
        Write-Host 'Report this output; README.md has what the sites should look like.' -ForegroundColor Cyan
    }

    <#
    .SYNOPSIS
    Overwrites one byte at a known offset, reporting what moved.

    .DESCRIPTION
    Reports the byte as changed, or as already holding the value asked for,
    so a run says which of its sites did anything.
    #>
    function Write-ByteAt {
        param ([byte[]]$Bytes, [int]$Address, [byte]$NewValue, [string]$Description)
        $oldValue = $Bytes[$Address]
        if ($oldValue -eq $NewValue) {
            Write-Host "$Description`: already 0x$($oldValue.ToString('X2'))"
        }
        else {
            $Bytes[$Address] = $NewValue
            $where = $Address.ToString('X')
            Write-Host "$Description`: 0x$where 0x$($oldValue.ToString('X2')) -> 0x$($NewValue.ToString('X2'))"
        }
    }
}

process {
    $setToggle = $PSBoundParameters.ContainsKey('TogglePattern')
    if ($ToggleProbe) {
        if ($setToggle) {
            throw '-TogglePattern and -ToggleProbe both set the toggle. Give one.'
        }
        $TogglePattern = [byte]$probes[$ToggleProbe].Byte
        $setToggle = $true
    }
    if ($setToggle -and $TogglePattern -eq 0) {
        throw '-TogglePattern 0 never drives the motor. Give a pattern with at least one bit set.'
    }

    if ($Rom -and $PSBoundParameters.ContainsKey('Makefile')) {
        throw '-Rom and -Makefile both name the ROM to patch. Give one.'
    }

    # The gate is written when -HoldGate asks for it, or when a preset carries a
    # value to restore. Left alone otherwise, so holding it is a decision rather
    # than something hand tuning does on the way past.
    $gateValue = [byte]0xFF
    $setGate = $HoldGate.IsPresent
    $setWall = $PSBoundParameters.ContainsKey('WallThreshold')
    $setCollisionFrames = $PSBoundParameters.ContainsKey('CollisionFrames')
    $setCollisionThreshold = $PSBoundParameters.ContainsKey('CollisionThreshold')
    # A start length implies the skip below, which is not the same as asking for it
    # and does not belong in the file name.
    $skipCollisionAsked = $SkipCollisionDuration.IsPresent
    if ($PSCmdlet.ParameterSetName -eq 'Preset') {
        $chosen = $presets[$Preset]
        $isPlaceholder = -not ($chosen.ContainsKey('GateValue') -or $chosen.ContainsKey('StartFrames'))
        if ($isPlaceholder) {
            # Point at the one measured board rather than a literal, so this cannot
            # drift from the table above.
            $start = $presets.GBMake
            throw (
                "The $Preset preset is a placeholder: no values for that cartridge yet. " +
                'Measure it with rumble-pulse.gb, or start from the GBMake value, ' +
                "-StartFrames $($start.StartFrames), then report what suits the board so " +
                'the preset can carry it.'
            )
        }
        if ($chosen.ContainsKey('StartFrames')) { $StartFrames = $chosen.StartFrames }
        if ($chosen.ContainsKey('SustainFrames')) { $SustainFrames = $chosen.SustainFrames }
        if ($chosen.ContainsKey('CoastGap')) { $CoastGap = $chosen.CoastGap }
        if ($chosen.ContainsKey('GateValue')) {
            $gateValue = [byte]$chosen.GateValue
            $setGate = $true
        }
        if ($chosen.ContainsKey('CollisionFrames')) {
            $CollisionFrames = $chosen.CollisionFrames
            $setCollisionFrames = $true
        }
        # Original carries the shipped thresholds so it can restore them, but an
        # explicit value is the caller saying what they want, so it wins.
        if ($chosen.ContainsKey('CollisionThreshold') -and -not $setCollisionThreshold) {
            $CollisionThreshold = $chosen.CollisionThreshold
            $setCollisionThreshold = $true
        }
        if ($chosen.ContainsKey('WallThreshold') -and -not $setWall) {
            $WallThreshold = $chosen.WallThreshold
            $setWall = $true
        }
        Write-Host "Preset: $Preset ($($chosen.Note))"
    }
    else {
        # Only what will actually be written, so the line is not a list of defaults
        # the run is about to ignore.
        $doing = [System.Collections.Generic.List[string]]::new()
        if ($StartFrames) { $doing.Add("start length $StartFrames, sustain $SustainFrames, coast gap $CoastGap") }
        if ($HoldGate) { $doing.Add('gate held on') }
        if (-not $SkipCollisionDuration) { $doing.Add("$CollisionFrames collision frame(s)") }
        if ($setCollisionThreshold) { $doing.Add("collision threshold $CollisionThreshold") }
        if ($setWall) { $doing.Add("wall threshold $WallThreshold") }
        Write-Host "Manual: $($doing -join ', ')"
    }

    # Writing the duration after the rescale would put the shipped 1 back over it
    # and undo the one site the patch exists for.
    if ($StartFrames -and -not $setCollisionFrames) {
        $SkipCollisionDuration = $true
    }

    if ($ToggleProbe) {
        Write-Host "Toggle probe: $ToggleProbe ($($probes[$ToggleProbe].Note))"
    }

    if ($HoldGate -and ($StartFrames -or $setToggle)) {
        # A held gate drives solidly for the whole duration, so every pattern reads
        # as $ff and its shape stops mattering. Nothing is left to widen or probe.
        throw (
            '-HoldGate makes every pattern solid, so there is nothing left for a start length or a ' +
            'toggle pattern to change. Give one or the other.'
        )
    }

    # Every byte this can write, tested after the preset has had its say. Asking
    # whether anything is left is what makes a preset's start length, or a
    # threshold, reason enough to run with the collision duration skipped.
    $willWrite = (
        $setGate -or
        $StartFrames -or
        $setToggle -or
        $setCollisionThreshold -or
        (-not $SkipCollisionDuration) -or
        $setWall
    )
    if (-not $willWrite) {
        throw (
            'Nothing left to patch: the collision duration is skipped, and no start length, ' +
            'threshold, toggle pattern or -HoldGate was given. Give one of those.'
        )
    }

    if (-not $Rom) {
        # A disassembly's Makefile is the one place that names what it builds, and
        # pokepinball and pokepinball-generations build different files, so this
        # reads the name rather than assuming it. ROM is relative to the Makefile,
        # so that is where the built file is looked for.
        if (-not (Test-Path -LiteralPath $Makefile)) {
            throw (
                "No Makefile at $Makefile, so there is no build output to default to. " +
                'Give -Rom, or -Makefile pointing at a disassembly Makefile.'
            )
        }
        $root = Split-Path -Parent (Convert-Path -LiteralPath $Makefile)
        $declared = Select-String -LiteralPath $Makefile -Pattern '^\s*ROM\s*:?=\s*(\S+)' |
            Select-Object -First 1
        if (-not $declared) {
            throw "The Makefile in $root names no ROM, so this is not a disassembly checkout. Give -Rom."
        }
        $built = $declared.Matches[0].Groups[1].Value
        $candidate = Join-Path $root $built
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "The Makefile builds $built, which is not there yet. Run make first, or pass -Rom."
        }
        $Rom = $candidate
        Write-Host "ROM: $Rom (this checkout's build output)"
    }
    if (-not (Test-Path -LiteralPath $Rom)) {
        throw "There is no file at $Rom."
    }
    $romItem = Get-Item -LiteralPath $Rom
    $bytes = Get-Content -LiteralPath $romItem.FullName -AsByteStream -Raw
    $original = $bytes.Clone()

    if (-not $OutFile) {
        # The settings go in the name, so trying several in one sitting leaves
        # files that can be told apart afterwards instead of one name overwritten
        # repeatedly. Nothing reads this back; it is for the person flashing them.
        # Bracketed, the way GoodTools and TOSEC mark an unofficial change, with the
        # settings in parentheses inside it: the brackets say the file was modified,
        # and everything in them describes that modification. The game already has
        # rumble, so "rumble fix" rather than "rumble".
        #
        # Each letter appears only if that byte was written, so the name never
        # claims a setting the run did not apply. A start length sets the collision
        # duration by rescaling, so f drops out when it is given.
        $gates = ''
        # g for a held gate, which is the modification. A preset restoring it to the
        # shipped $01 writes the byte too, but a stock value is not worth a letter.
        if ($setGate -and $gateValue -eq 0xFF) { $gates += 'g' }
        if (-not $SkipCollisionDuration) { $gates += "f$CollisionFrames" }
        if ($setCollisionThreshold) { $gates += "t$CollisionThreshold" }
        if ($setWall) { $gates += "w$WallThreshold" }
        $settings = [System.Collections.Generic.List[string]]::new()
        if ($gates) { $settings.Add($gates) }
        if ($StartFrames) { $settings.Add("s$StartFrames") }
        if ($setToggle) { $settings.Add('toggle{0:x2}' -f $TogglePattern) }
        if ($skipCollisionAsked) { $settings.Add('nocollision') }
        $tag = "rumble fix ($($settings -join '-'))"
        if ($Author) { $tag += " by $Author" }
        $OutFile = Join-Path $romItem.DirectoryName "$($romItem.BaseName) [$tag]$($romItem.Extension)"
    }
    # -OutFile names a file that does not exist yet, so no cmdlet will resolve it
    # and Resolve-Path would throw. This is the provider-aware way to get there.
    $resolvedOut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    if ($resolvedOut -eq $romItem.FullName) {
        throw "-OutFile resolves to $Rom itself. Give a different path; this never overwrites -Rom."
    }

    # The VBlank gate is the anchor for both edits, and is located with its WRAM
    # address and its "and" operand both left open: rrca; ld [wRumblePattern], a;
    # and n; jr z, .rumbleOff. Reading the address out of the match rather than
    # assuming $D803 is what lets this work on a build whose WRAM sits elsewhere,
    # and leaving the operand open is what lets -Preset Original find a patched
    # ROM in order to put it back.
    $gateDescription = 'VBlank rumble gate (and operand)'
    $gatePattern = @(0x0F, 0xEA, -1, -1, 0xE6, -1, 0x28)
    try {
        $gateOffset = Get-SoleMatch -Bytes $bytes -Pattern $gatePattern -Description $gateDescription
    }
    catch {
        Write-Warning $_.Exception.Message
        Show-WhatIsThere -Bytes $bytes
        throw
    }
    $gateAddress = $gateOffset + 5

    # A held gate is the one mark a patched ROM carries that this can read back,
    # since the rescale maps several patterns onto one and cannot be recognised.
    # Every edit writes an absolute value, so a second pass would change nothing;
    # this refuses anyway, because reaching here means the wrong file was given.
    if ($setGate -and $gateValue -eq 0xFF -and $bytes[$gateAddress] -eq 0xFF) {
        throw (
            "$gateDescription`: this ROM already holds the gate, at 0x$($gateAddress.ToString('X')), " +
            'so it has been patched before. Patch the unmodified ROM, or use -Preset Original to put ' +
            'this one back first.'
        )
    }

    $patternAddress = ([int]$bytes[$gateOffset + 3] -shl 8) -bor [int]$bytes[$gateOffset + 2]
    $durationAddress = $patternAddress + 1
    Write-Host ('wRumblePattern is at ${0:X4}, so wRumbleDuration is ${1:X4}' -f $patternAddress, $durationAddress)

    if ($setGate) {
        Write-ByteAt -Bytes $bytes -Address $gateAddress -NewValue $gateValue -Description $gateDescription
    }

    if ($StartFrames) {
        $setPattern = @(0x3E, -1, 0xEA, ($patternAddress -band 0xFF), ($patternAddress -shr 8))
        $patternSites = Find-BytePattern -Haystack $bytes -Pattern $setPattern
        if ($patternSites.Count -eq 0) {
            throw 'No rumble pattern sites found, which contradicts the gate site above.'
        }

        # A pattern is one byte rotated once per frame, so it is an 8-frame
        # schedule that repeats. The sparse ones put single frames of drive under a
        # motor that cannot start that fast, and no duration reaches them: a longer
        # event is more frames of the same pulse, not a wider one.
        $rescaled = @{}
        $rescaledCount = 0
        foreach ($offset in $patternSites) {
            $old = [int]$bytes[$offset + 1]
            if ($old -eq 0xFF) { continue }
            if (-not $rescaled.ContainsKey($old)) {
                $rescaled[$old] = Get-RescaledPattern -Pattern $old -StartFrames $StartFrames `
                    -SustainFrames $SustainFrames -CoastGap $CoastGap
            }
            $new = [int]$rescaled[$old]
            if ($new -eq 0) {
                throw "Rescaling $('0x{0:X2}' -f $old) produced a zero pattern, which never drives the motor."
            }
            if ($new -ne $old) {
                $bytes[$offset + 1] = [byte]$new
                $rescaledCount++
            }
        }
        foreach ($old in ($rescaled.Keys | Sort-Object)) {
            if ($rescaled[$old] -ne $old) {
                Write-Host ('  pattern ${0:X2} -> ${1:X2}   {2} -> {3}' -f $old, $rescaled[$old],
                    ((0..7 | ForEach-Object { ($old -shr $_) -band 1 }) -join ''),
                    ((0..7 | ForEach-Object { ($rescaled[$old] -shr $_) -band 1 }) -join ''))
            }
        }
        Write-Host "Rescaled to $StartFrames-frame pulses: $rescaledCount of $($patternSites.Count) pattern site(s)"

        # An all-ones pattern has no pulse to widen; its problem is that the event
        # ends before the motor is up. STRONG is comfortably past the threshold
        # rather than sitting on it, as a 3 frame event needs when 3
        # frames is only just perceptible. Events of 8 frames or more are already
        # well past it and are left alone.
        $strong = [math]::Ceiling(1.5 * $StartFrames)
        $raised = 0
        foreach ($offset in $patternSites) {
            if ($bytes[$offset + 1] -ne 0xFF) { continue }
            if ($bytes[$offset + 5] -ne 0x3E -or $bytes[$offset + 7] -ne 0xEA) { continue }
            # The store that follows has to be to wRumbleDuration. Without this the
            # shape alone would match a pattern store followed by any other store,
            # and this would raise a byte it had not identified.
            if ($bytes[$offset + 8] -ne ($durationAddress -band 0xFF)) { continue }
            if ($bytes[$offset + 9] -ne ($durationAddress -shr 8)) { continue }
            $durationAt = $offset + 6
            $old = [int]$bytes[$durationAt]
            if ($old -eq 0 -or $old -ge 8 -or $old -ge $strong) { continue }
            $bytes[$durationAt] = [byte]$strong
            $raised++
        }
        Write-Host "Raised $raised solid event(s) under 8 frames to $strong frames"
    }

    if ($setToggle) {
        # The options-screen toggle is the sparse event with much the longest
        # duration, and that is what makes it findable without knowing the byte: it
        # runs for about a second where every other sparse event is gone in a
        # fraction of one. Being a menu, it also needs no ball, no collision and no
        # velocity, so it isolates the pattern from everything else.
        $anyPattern = @(0x3E, -1, 0xEA, ($patternAddress -band 0xFF), ($patternAddress -shr 8),
            0x3E, -1, 0xEA, ($durationAddress -band 0xFF), ($durationAddress -shr 8))
        $sparse = @()
        foreach ($offset in (Find-BytePattern -Haystack $bytes -Pattern $anyPattern)) {
            if ($bytes[$offset + 1] -ne 0xFF) {
                $sparse += [pscustomobject]@{ Offset = $offset; Duration = [int]$bytes[$offset + 6] }
            }
        }
        if ($sparse.Count -eq 0) {
            throw 'No sparse rumble event found, so there is no options-screen toggle to set.'
        }
        $longest = ($sparse | Measure-Object -Property Duration -Maximum).Maximum
        $candidates = @($sparse | Where-Object { $_.Duration -eq $longest })
        if ($candidates.Count -gt 1) {
            throw (
                "$($candidates.Count) sparse events share the longest duration of $longest frames, " +
                'so the options-screen toggle cannot be told apart. Refusing to guess.'
            )
        }
        Write-ByteAt -Bytes $bytes -Address ($candidates[0].Offset + 1) -NewValue $TogglePattern `
            -Description "Options-screen toggle pattern ($longest frames)"
    }

    # The site is located for either byte, since the two are written independently
    # and a run can want the threshold with the duration skipped.
    if (-not $SkipCollisionDuration -or $setCollisionThreshold) {
        # ld a, d ; cp n ; jr c ; ld a, $ff ; ld [wRumblePattern], a ; ld a, n ;
        # ld [wRumbleDuration], a. The velocity test is what anchors this: the
        # four rumble stores on their own are the shape of every event in the
        # game, and the "cp n" shape occurs all over it, but only here do the two
        # meet. Both literals are left open so this finds the site whatever they
        # currently hold, so -Preset Original can find them to restore them.
        $collisionPattern = @(
            0x7A, 0xFE, -1, 0x38, -1,
            0x3E, 0xFF,
            0xEA, ($patternAddress -band 0xFF), ($patternAddress -shr 8),
            0x3E, -1,
            0xEA, ($durationAddress -band 0xFF), ($durationAddress -shr 8)
        )
        $collisionDescription = 'ApplyCollisionForces'
        try {
            $collisionOffset = Get-SoleMatch -Bytes $bytes -Pattern $collisionPattern `
                -Description $collisionDescription
        }
        catch {
            Write-Warning $_.Exception.Message
            Show-WhatIsThere -Bytes $bytes
            throw
        }
        if ($setCollisionThreshold) {
            Write-ByteAt -Bytes $bytes -Address ($collisionOffset + 2) -NewValue ([byte]$CollisionThreshold) `
                -Description "$collisionDescription threshold (rumble when ball velocity >= $CollisionThreshold)"
        }
        if (-not $SkipCollisionDuration) {
            Write-ByteAt -Bytes $bytes -Address ($collisionOffset + 11) -NewValue ([byte]$CollisionFrames) `
                -Description "$collisionDescription duration ($CollisionFrames frame(s))"
        }
    }

    if ($setWall) {
        # The wall handlers are the other velocity gate, and there are far more of
        # them than the one in ApplyCollisionForces. What identifies them is the
        # lockout that follows: ld a, [wRumbleDuration] ; and a ; then a return if
        # it is still running, so a hit landing inside the previous burst is
        # dropped. Eighteen sites return with "ret nz" and one with "jr nz", so
        # anchoring on the lockout finds all of them where anchoring on the whole
        # instruction sequence misses that one. The "cp n" sits within a few bytes
        # ahead of it.
        $wallSites = [System.Collections.Generic.List[int]]::new()
        for ($i = 8; $i -lt $bytes.Length - 8; $i++) {
            if ($bytes[$i] -ne 0xFA) { continue }
            if ($bytes[$i + 1] -ne ($durationAddress -band 0xFF)) { continue }
            if ($bytes[$i + 2] -ne ($durationAddress -shr 8)) { continue }
            if ($bytes[$i + 3] -ne 0xA7) { continue }
            if ($bytes[$i + 4] -ne 0xC0 -and $bytes[$i + 4] -ne 0x20) { continue }
            for ($back = 2; $back -le 8; $back++) {
                if ($bytes[$i - $back] -eq 0xFE) {
                    $wallSites.Add($i - $back + 1)
                    break
                }
            }
        }
        if ($wallSites.Count -eq 0) {
            throw 'No lockout-guarded wall handlers found, so there is no wall threshold to set.'
        }
        $wallChanged = 0
        $wallWas = @{}
        foreach ($at in $wallSites) {
            $wallWas[[int]$bytes[$at]] = 1 + ($wallWas[[int]$bytes[$at]] ?? 0)
            if ($bytes[$at] -ne $WallThreshold) {
                $bytes[$at] = [byte]$WallThreshold
                $wallChanged++
            }
        }
        $from = ($wallWas.Keys | Sort-Object | ForEach-Object { "$_" }) -join '/'
        Write-Host ("Wall handler threshold $from -> ${WallThreshold}: " +
            "$wallChanged of $($wallSites.Count) site(s) changed")
    }

    $changed = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -ne $original[$i]) { $changed++ }
    }
    if ($changed -eq 0) {
        Write-Host ''
        Write-Host 'Every byte already holds the value asked for, so nothing was written.'
        if ($PSCmdlet.ParameterSetName -eq 'Preset' -and -not $setToggle -and -not $StartFrames) {
            Write-Host "  The $Preset preset is the values the game ships. A motor that needs more than"
            Write-Host '  a frame to start wants -Preset GBMake, or a start length measured for it.'
        }
    }
    else {
        Set-Content -LiteralPath $resolvedOut -AsByteStream -Value $bytes
        Write-Host "$changed byte(s) changed. Wrote $resolvedOut"
    }
}
