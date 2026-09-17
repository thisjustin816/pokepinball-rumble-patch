#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
Checks Set-PinballRumble.ps1's byte patching without a real ROM.

.DESCRIPTION
The byte sequences are RGBDS's encoding of the instruction sequences the
README describes, checked by assembling those sequences with RGBDS 0.9.1.
The WRAM addresses in these fixtures are the fixtures' own, since the
script reads addresses out of the ROM rather than assuming them. What is
tested here is the tool's own logic, run end to end through its public
interface: it finds the right byte, refuses an ambiguous or absent
pattern, and never touches a file it was not asked to.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:tool = Join-Path $repoRoot 'Set-PinballRumble.ps1'

    # rrca; ld [wRumblePattern], a; and $1; jr z, .rumbleOff
    # wRumblePattern at $D803, so wRumbleDuration is $D804.
    $script:gateBytes = [byte[]](0x0F, 0xEA, 0x03, 0xD8, 0xE6, 0x01, 0x28, 0x04)

    # ApplyCollisionForces: the velocity test, then the rumble stores.
    #   ld a, d; cp 3; jr c, .applyforces
    #   ld a, $ff; ld [wRumblePattern], a; ld a, 1; ld [wRumbleDuration], a
    $script:collisionBytes = [byte[]](
        0x7A, 0xFE, 0x03, 0x38, 0x0A,
        0x3E, 0xFF, 0xEA, 0x03, 0xD8, 0x3E, 0x01, 0xEA, 0x04, 0xD8
    )
    $script:thresholdIndex = 2
    $script:durationIndex = 11

    # A wall handler: cp 2; ret c; the lockout; then the $05 stores.
    $script:wallBytes = [byte[]](
        0xFE, 0x02, 0xD8,
        0xFA, 0x04, 0xD8, 0xA7, 0xC0,
        0x3E, 0x05, 0xEA, 0x03, 0xD8, 0x3E, 0x08, 0xEA, 0x04, 0xD8
    )
    $script:wallThresholdIndex = 1
    $script:wallPatternIndex = 9

    # The options-screen toggle, and a bumper, as plain stores.
    $script:toggleBytes = [byte[]](0x3E, 0x55, 0xEA, 0x03, 0xD8, 0x3E, 0x40, 0xEA, 0x04, 0xD8)
    $script:bumperBytes = [byte[]](0x3E, 0xFF, 0xEA, 0x03, 0xD8, 0x3E, 0x03, 0xEA, 0x04, 0xD8)

    <#
    .SYNOPSIS
    Writes a ROM holding one of each site the script looks for.
    #>
    function Write-TestRom {
        param ([string]$Path, [int]$GateCopies = 1, [int]$Length = 0x8000)
        $bytes = [byte[]]::new($Length)
        for ($i = 0; $i -lt $Length; $i++) { $bytes[$i] = 0xFF }
        $offset = 0x150
        for ($i = 0; $i -lt $GateCopies; $i++) {
            [Array]::Copy($gateBytes, 0, $bytes, $offset, $gateBytes.Length)
            $offset += $gateBytes.Length + 0x10
        }
        [Array]::Copy($collisionBytes, 0, $bytes, 0x200, $collisionBytes.Length)
        [Array]::Copy($wallBytes, 0, $bytes, 0x300, $wallBytes.Length)
        [Array]::Copy($toggleBytes, 0, $bytes, 0x400, $toggleBytes.Length)
        [Array]::Copy($bumperBytes, 0, $bytes, 0x500, $bumperBytes.Length)
        Set-Content -LiteralPath $Path -AsByteStream -Value $bytes
    }

    <#
    .SYNOPSIS
    The one place these tests say how a ROM is read back.
    #>
    function Get-RomByte {
        param ([string]$Path)
        Get-Content -LiteralPath $Path -AsByteStream -Raw
    }
}

Describe 'Pinball rumble patch' {
    BeforeEach {
        $script:rom = Join-Path $TestDrive 'pinball.gbc'
        Write-TestRom -Path $rom
    }

    Context 'rescaling patterns' {
        It 'gives every sparse pulse the start length, from rest' {
            # $55 plays one frame on, one off. At three frames the first pulse
            # has to break static friction; the ones behind a single frame of
            # gap ride on a motor that never stopped, so they stay short.
            $out = Join-Path $TestDrive 'e3.gbc'
            & $tool -Rom $rom -StartFrames 3 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x401] | Should -Be 0x57      # $55 -> 11101010
            $after[0x300 + $wallPatternIndex] | Should -Be 0x17   # $05 -> 11101000
        }

        It 'leaves a solid pattern alone and raises its duration instead' {
            # $FF has no pulse to widen. STRONG is ceil(1.5 * 3) = 5.
            $out = Join-Path $TestDrive 'solid.gbc'
            & $tool -Rom $rom -StartFrames 3 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x501] | Should -Be 0xFF
            $after[0x506] | Should -Be 5
        }

        It 'leaves the gate alone, since nothing asked to hold it' {
            $out = Join-Path $TestDrive 'gate-untouched.gbc'
            & $tool -Rom $rom -StartFrames 3 -OutFile $out
            (Get-RomByte -Path $out)[0x155] | Should -Be 0x01
        }

        It 'refuses -HoldGate with a start length, which it would make pointless' {
            { & $tool -Rom $rom -StartFrames 3 -HoldGate -ErrorAction Stop } |
                Should -Throw '*nothing left for a start length*'
        }

        It 'never writes a zero pattern, which would silence the event' {
            $out = Join-Path $TestDrive 'nonzero.gbc'
            & $tool -Rom $rom -StartFrames 4 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x401] | Should -Not -Be 0
            $after[0x300 + $wallPatternIndex] | Should -Not -Be 0
        }

        It 'rescales at every start length it accepts, without falling over' {
            # 7 is the ceiling: an 8-frame pulse fills the loop and leaves no
            # room for a gap, so nothing would be left to drop to make it fit.
            foreach ($frames in 1..7) {
                $out = Join-Path $TestDrive "s$frames.gbc"
                & $tool -Rom $rom -StartFrames $frames -OutFile $out
                $after = Get-RomByte -Path $out
                $after[0x401] | Should -Not -Be 0
                $after[0x300 + $wallPatternIndex] | Should -Not -Be 0
            }
        }

        It 'refuses a start length that cannot leave room for a gap' {
            { & $tool -Rom $rom -StartFrames 8 -ErrorAction Stop } |
                Should -Throw '*maximum allowed range*'
        }

        It 'raises only durations stored to wRumbleDuration' {
            # A pattern store followed by a store somewhere else has the same
            # shape, so the site is identified by its target, not its shape.
            $decoy = Join-Path $TestDrive 'decoy.gbc'
            Write-TestRom -Path $decoy
            $bytes = Get-RomByte -Path $decoy
            # ld a,$ff; ld [wRumblePattern],a; ld a,3; ld [$C000],a
            [Array]::Copy(
                [byte[]](0x3E, 0xFF, 0xEA, 0x03, 0xD8, 0x3E, 0x03, 0xEA, 0x00, 0xC0),
                0, $bytes, 0x600, 10)
            Set-Content -LiteralPath $decoy -AsByteStream -Value $bytes

            $out = Join-Path $TestDrive 'decoy-out.gbc'
            & $tool -Rom $decoy -StartFrames 3 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x506] | Should -Be 5   # the real bumper duration, raised
            $after[0x606] | Should -Be 3   # the decoy, left alone
        }
    }

    Context 'velocity gates' {
        It 'sets the wall handlers, which are separate from the collision' {
            $out = Join-Path $TestDrive 'wall.gbc'
            & $tool -Rom $rom -WallThreshold 1 -SkipCollisionDuration -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x300 + $wallThresholdIndex] | Should -Be 1
            $after[0x200 + $thresholdIndex] | Should -Be 3   # collision untouched
        }

        It 'writes a threshold asked for alongside a preset' {
            # The thresholds are game logic, so no motor preset owns them and
            # both combine with one. A start length must not silence them
            # either: it governs the duration beside them, not the gate.
            $out = Join-Path $TestDrive 'preset-gates.gbc'
            & $tool -Rom $rom -Preset GBMake -CollisionThreshold 1 -WallThreshold 1 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x200 + $thresholdIndex] | Should -Be 1
            $after[0x300 + $wallThresholdIndex] | Should -Be 1
            $after[0x401] | Should -Be 0x57   # still rescaled
        }

        It 'writes a threshold asked for alongside a start length' {
            $out = Join-Path $TestDrive 'manual-gates.gbc'
            & $tool -Rom $rom -StartFrames 3 -CollisionThreshold 1 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x200 + $thresholdIndex] | Should -Be 1
            $after[0x200 + $durationIndex] | Should -Be 5   # rescaled, not reset to 1
        }

        It 'leaves the threshold alone when nothing asked for one' {
            $out = Join-Path $TestDrive 'no-thresh.gbc'
            & $tool -Rom $rom -Preset GBMake -OutFile $out
            (Get-RomByte -Path $out)[0x200 + $thresholdIndex] | Should -Be 3
        }

        It 'holds the gate only when asked, so holding it is opt in' {
            $plain = Join-Path $TestDrive 'gate-default.gbc'
            & $tool -Rom $rom -CollisionFrames 4 -OutFile $plain
            (Get-RomByte -Path $plain)[0x155] | Should -Be 0x01

            $held = Join-Path $TestDrive 'gate-held.gbc'
            & $tool -Rom $rom -CollisionFrames 4 -HoldGate -OutFile $held
            (Get-RomByte -Path $held)[0x155] | Should -Be 0xFF
        }

        It 'refuses -HoldGate alongside a preset, which carries its own gate' {
            { & $tool -Rom $rom -Preset GBMake -HoldGate -ErrorAction Stop } |
                Should -Throw '*Parameter set cannot be resolved*'
        }

        It 'refuses a ROM whose gate is already held' {
            $held = Join-Path $TestDrive 'already.gbc'
            & $tool -Rom $rom -CollisionFrames 4 -HoldGate -OutFile $held
            { & $tool -Rom $held -CollisionFrames 4 -HoldGate -ErrorAction Stop } |
                Should -Throw '*has been patched before*'
        }

        It 'sets the collision gate without touching the wall handlers' {
            $out = Join-Path $TestDrive 'coll.gbc'
            & $tool -Rom $rom -CollisionThreshold 1 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x200 + $thresholdIndex] | Should -Be 1
            $after[0x300 + $wallThresholdIndex] | Should -Be 2   # wall untouched
        }

        It 'finds a wall handler that returns with jr nz rather than ret nz' {
            $jr = Join-Path $TestDrive 'jrnz.gbc'
            Write-TestRom -Path $jr
            $bytes = Get-RomByte -Path $jr
            $bytes[0x300 + 7] = 0x20   # ret nz -> jr nz
            Set-Content -LiteralPath $jr -AsByteStream -Value $bytes
            $out = Join-Path $TestDrive 'jrnz-out.gbc'
            & $tool -Rom $jr -WallThreshold 1 -SkipCollisionDuration -OutFile $out
            (Get-RomByte -Path $out)[0x300 + $wallThresholdIndex] | Should -Be 1
        }
    }

    Context 'presets' {
        It 'rescales under GBMake, which carries a measured start length' {
            $out = Join-Path $TestDrive 'gbmake.gbc'
            & $tool -Rom $rom -Preset GBMake -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x401] | Should -Be 0x57
            $after[0x155] | Should -Be 0x01   # gate left alone
        }

        It 'writes nothing under Original, which is the default' {
            $out = Join-Path $TestDrive 'original.gbc'
            & $tool -Rom $rom -OutFile $out
            Test-Path -LiteralPath $out | Should -BeFalse
        }

        It 'leaves a ROM alone for a board that rumbles unpatched' {
            $out = Join-Path $TestDrive 'ali.gbc'
            & $tool -Rom $rom -Preset AliExpress -OutFile $out
            Test-Path -LiteralPath $out | Should -BeFalse
        }

        It 'refuses a preset nobody has measured' {
            { & $tool -Rom $rom -Preset InsideGadgets -OutFile (Join-Path $TestDrive 'ig.gbc') -ErrorAction Stop } |
                Should -Throw '*placeholder*'
        }

        It 'puts both gates and the collision duration back with Original' {
            # Patterns cannot come back: rescaling maps several onto one.
            $patched = Join-Path $TestDrive 'patched.gbc'
            & $tool -Rom $rom -CollisionThreshold 0 -CollisionFrames 9 -WallThreshold 0 -OutFile $patched
            $restored = Join-Path $TestDrive 'restored.gbc'
            & $tool -Rom $patched -Preset Original -OutFile $restored
            $after = Get-RomByte -Path $restored
            $after[0x155] | Should -Be 0x01
            $after[0x200 + $thresholdIndex] | Should -Be 3
            $after[0x200 + $durationIndex] | Should -Be 1
            $after[0x300 + $wallThresholdIndex] | Should -Be 2
        }
    }

    Context 'the options-screen toggle probe' {
        It 'sets only the toggle, which is the longest sparse event' {
            $out = Join-Path $TestDrive 'probe.gbc'
            $before = Get-RomByte -Path $rom
            & $tool -Rom $rom -ToggleProbe Mixed -SkipCollisionDuration -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x401] | Should -Be 0x73
            $changed = 0
            for ($i = 0; $i -lt $after.Length; $i++) { if ($after[$i] -ne $before[$i]) { $changed++ } }
            $changed | Should -Be 1
        }

        It 'refuses -TogglePattern and -ToggleProbe together' {
            { & $tool -Rom $rom -TogglePattern 0x73 -ToggleProbe Mixed -ErrorAction Stop } |
                Should -Throw '*both set the toggle*'
        }

        It 'refuses a zero toggle pattern, which never drives the motor' {
            { & $tool -Rom $rom -TogglePattern 0 -ErrorAction Stop } | Should -Throw '*never drives the motor*'
        }
    }

    Context 'refusing what it cannot identify' {
        It 'refuses a ROM with no gate site' {
            $noGate = Join-Path $TestDrive 'no-gate.gbc'
            Write-TestRom -Path $noGate -GateCopies 0
            { & $tool -Rom $noGate -Preset GBMake -ErrorAction Stop } | Should -Throw '*pattern not found*'
        }

        It 'refuses a ROM with an ambiguous gate site' {
            $ambiguous = Join-Path $TestDrive 'ambiguous.gbc'
            Write-TestRom -Path $ambiguous -GateCopies 2
            { & $tool -Rom $ambiguous -Preset GBMake -ErrorAction Stop } | Should -Throw '*found 2 times*'
        }

        It 'refuses when both changes are skipped and nothing else was asked for' {
            # Manual, so no preset supplies a start length or a threshold.
            { & $tool -Rom $rom -CollisionFrames 4 -SkipCollisionDuration -ErrorAction Stop } |
                Should -Throw '*Nothing left to patch*'
        }

        It 'still runs under both skips when a preset brings a start length' {
            # The refusal is about whether a byte gets written, not about which
            # switches were given: GBMake rescales whatever the skips say.
            $out = Join-Path $TestDrive 'skips-with-preset.gbc'
            & $tool -Rom $rom -Preset GBMake -SkipCollisionDuration -OutFile $out
            (Get-RomByte -Path $out)[0x401] | Should -Be 0x57
        }

        It 'still runs under both skips when a threshold was asked for' {
            $out = Join-Path $TestDrive 'skips-with-threshold.gbc'
            & $tool -Rom $rom -CollisionFrames 4 -SkipCollisionDuration `
                -CollisionThreshold 1 -OutFile $out
            $after = Get-RomByte -Path $out
            $after[0x200 + $thresholdIndex] | Should -Be 1
            $after[0x200 + $durationIndex] | Should -Be 1   # duration still skipped
        }

        It 'refuses a preset and a hand-tuned motor value together' {
            { & $tool -Rom $rom -Preset GBMake -StartFrames 4 -ErrorAction Stop } |
                Should -Throw '*Parameter set cannot be resolved*'
        }

        It 'refuses an -OutFile that resolves to -Rom' {
            { & $tool -Rom $rom -Preset GBMake -OutFile $rom -ErrorAction Stop } |
                Should -Throw '*never overwrites*'
        }

        It 'refuses -Rom and -Makefile together' {
            { & $tool -Rom $rom -Makefile (Join-Path $TestDrive 'Makefile') -ErrorAction Stop } |
                Should -Throw '*both name the ROM*'
        }
    }

    Context 'finding the ROM' {
        It 'takes it from a Makefile, without living in the checkout' {
            $checkout = Join-Path $TestDrive 'checkout'
            $null = New-Item -ItemType Directory -Force $checkout
            Set-Content -LiteralPath (Join-Path $checkout 'Makefile') -Value 'ROM := PinballGenerations.gbc'
            Write-TestRom -Path (Join-Path $checkout 'PinballGenerations.gbc')
            $out = Join-Path $TestDrive 'from-checkout.gbc'
            & $tool -Makefile (Join-Path $checkout 'Makefile') -Preset GBMake -OutFile $out
            (Get-RomByte -Path $out)[0x401] | Should -Be 0x57
        }

        It 'defaults -Makefile to the current directory' {
            $checkout = Join-Path $TestDrive 'cwd-checkout'
            $null = New-Item -ItemType Directory -Force $checkout
            Set-Content -LiteralPath (Join-Path $checkout 'Makefile') -Value 'ROM := pokepinball.gbc'
            Write-TestRom -Path (Join-Path $checkout 'pokepinball.gbc')
            $out = Join-Path $TestDrive 'from-cwd.gbc'
            Push-Location $checkout
            try { & $tool -Preset GBMake -OutFile $out }
            finally { Pop-Location }
            (Get-RomByte -Path $out)[0x401] | Should -Be 0x57
        }

        It 'says which file the Makefile builds when it is not there yet' {
            $checkout = Join-Path $TestDrive 'unbuilt'
            $null = New-Item -ItemType Directory -Force $checkout
            Set-Content -LiteralPath (Join-Path $checkout 'Makefile') -Value 'ROM := pokepinball.gbc'
            { & $tool -Makefile (Join-Path $checkout 'Makefile') -Preset GBMake -ErrorAction Stop } |
                Should -Throw '*pokepinball.gbc, which is not there yet*'
        }

        It 'refuses a path with no Makefile' {
            $plain = Join-Path $TestDrive 'not-a-checkout'
            $null = New-Item -ItemType Directory -Force $plain
            { & $tool -Makefile (Join-Path $plain 'Makefile') -Preset GBMake -ErrorAction Stop } |
                Should -Throw '*No Makefile*'
        }
    }

    Context 'output' {
        It 'writes to a chosen -OutFile' {
            $outFile = Join-Path $TestDrive 'chosen.gbc'
            & $tool -Rom $rom -Preset GBMake -OutFile $outFile
            Test-Path -LiteralPath $outFile | Should -BeTrue
        }

        It 'does not modify -Rom' {
            $before = Get-FileHash -LiteralPath $rom -Algorithm SHA256
            & $tool -Rom $rom -Preset GBMake
            (Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash | Should -Be $before.Hash
        }

        It 'names the output for its settings, so a session leaves comparable files' {
            # -Author here so these assert the settings rather than the default
            # credit, which its own test below covers.
            & $tool -Rom $rom -StartFrames 3 -Author 'x'
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (s3) by x].gbc') |
                Should -BeTrue

            & $tool -Rom $rom -StartFrames 4 -Author 'x'
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (s4) by x].gbc') |
                Should -BeTrue
        }

        It 'names the collision frames only when it wrote them' {
            & $tool -Rom $rom -CollisionFrames 4 -Author 'x'
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (f4) by x].gbc') |
                Should -BeTrue

            & $tool -Rom $rom -StartFrames 3 -CollisionFrames 4 -Author 'x'
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (f4-s3) by x].gbc') |
                Should -BeTrue
        }

        It 'credits the script author by default, and whoever -Author names' {
            & $tool -Rom $rom -StartFrames 3
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (s3) by thisjustin816].gbc') |
                Should -BeTrue

            & $tool -Rom $rom -StartFrames 4 -Author ''
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (s4)].gbc') | Should -BeTrue
        }

        It 'names the gate only when -HoldGate asked for it' {
            & $tool -Rom $rom -CollisionFrames 4 -HoldGate -Author 'x'
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (gf4) by x].gbc') |
                Should -BeTrue

            & $tool -Rom $rom -CollisionFrames 4 -Author 'x'
            Test-Path -LiteralPath (Join-Path $TestDrive 'pinball [rumble fix (f4) by x].gbc') |
                Should -BeTrue
        }

        It 'refuses an -Author that cannot go in a filename' {
            { & $tool -Rom $rom -StartFrames 3 -Author 'a/b' -ErrorAction Stop } |
                Should -Throw '*cannot contain*'
        }

        It 'writes a readable ROM despite the brackets being wildcard characters' {
            & $tool -Rom $rom -StartFrames 3 -Author 'x'
            $out = Join-Path $TestDrive 'pinball [rumble fix (s3) by x].gbc'
            (Get-Item -LiteralPath $out).Length | Should -Be 0x8000
            (Get-RomByte -Path $out)[0x401] | Should -Be 0x57
        }
    }

    Context 'the collision duration under a start length' {
        # The rescale raises it, so writing -CollisionFrames afterwards would put
        # the shipped 1 back over the one site the patch exists for.
        It 'leaves the rescaled duration alone' {
            $out = Join-Path $TestDrive 'rescaled.gbc'
            & $tool -Rom $rom -StartFrames 3 -OutFile $out
            (Get-RomByte -Path $out)[0x200 + $durationIndex] | Should -Be 5
        }

        It 'still takes an explicit -CollisionFrames' {
            $out = Join-Path $TestDrive 'explicit.gbc'
            & $tool -Rom $rom -StartFrames 3 -CollisionFrames 1 -OutFile $out
            (Get-RomByte -Path $out)[0x200 + $durationIndex] | Should -Be 1
        }
    }

    Context 'finding the sites' {
        It 'patches a build whose wRumblePattern is not at $D803' {
            $moved = Join-Path $TestDrive 'moved.gbc'
            $bytes = [byte[]]::new(0x8000)
            for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = 0xFF }
            [Array]::Copy([byte[]](0x0F, 0xEA, 0x1A, 0xC9, 0xE6, 0x01, 0x28, 0x04), 0, $bytes, 0x150, 8)
            [Array]::Copy([byte[]](0x3E, 0x55, 0xEA, 0x1A, 0xC9, 0x3E, 0x40, 0xEA, 0x1B, 0xC9), 0, $bytes, 0x400, 10)
            Set-Content -LiteralPath $moved -AsByteStream -Value $bytes

            $out = Join-Path $TestDrive 'moved-out.gbc'
            & $tool -Rom $moved -StartFrames 3 -SkipCollisionDuration -OutFile $out
            (Get-RomByte -Path $out)[0x401] | Should -Be 0x57
        }

        It 'reads the ROM name from a Makefile with other rules in it' {
            $checkout = Join-Path $TestDrive 'busy-makefile'
            $null = New-Item -ItemType Directory -Force $checkout
            Set-Content -LiteralPath (Join-Path $checkout 'Makefile') -Value @(
                '.PHONY: all clean'
                'RGBASM := rgbasm'
                'ROM := pokepinball.gbc'
                'all: $(ROM)'
                "`t`$(RGBASM) -o `$@ `$<"
            )
            Write-TestRom -Path (Join-Path $checkout 'pokepinball.gbc')
            $out = Join-Path $TestDrive 'busy-out.gbc'
            & $tool -Makefile (Join-Path $checkout 'Makefile') -Preset GBMake -OutFile $out
            (Get-RomByte -Path $out)[0x401] | Should -Be 0x57
        }
    }

    Context 'what Original can and cannot put back' {
        It 'leaves raised solid durations raised, which the docs promise' {
            # Nothing records what a duration was before a start length raised
            # it, so this is a repair rather than a round trip.
            $patched = Join-Path $TestDrive 'raised.gbc'
            & $tool -Rom $rom -StartFrames 3 -OutFile $patched
            (Get-RomByte -Path $patched)[0x506] | Should -Be 5   # bumper 3 -> 5

            $restored = Join-Path $TestDrive 'raised-restored.gbc'
            & $tool -Rom $patched -Preset Original -OutFile $restored
            $after = Get-RomByte -Path $restored
            $after[0x506] | Should -Be 5                          # still raised
            $after[0x200 + $thresholdIndex] | Should -Be 3         # threshold is put back
            $after[0x300 + $wallThresholdIndex] | Should -Be 2
        }
    }
}
