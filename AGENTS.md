# Diagnostic development

Reusable Game Boy and Game Boy Color diagnostics have moved to
[Bacon Bit Bench](https://github.com/thisjustin816/bacon-bits). Use its
[release cartridges](https://github.com/thisjustin816/bacon-bits/releases/latest) and [manual](https://github.com/thisjustin816/bacon-bits/blob/main/MANUAL.md) for new runs.

`rumble-pulse/` is a historical standalone project. Use Rumble in the MBC5
Bacon Bit Bench cartridge for current calibration and pattern playback.

- Develop new diagnostic instruments, measurement features, fixes and diagnostic
  test coverage in Bacon Bit Bench. File diagnostic issues there.
- Preserve the old source, ROMs, tests and recorded hashes for reproduction.
  Keep current usage guidance pointed at Bacon Bit Bench.
- Maintain game patches and their game-specific debugging and tests in this
  repository. Move reusable diagnostic work to Bacon Bit Bench.
- Keep public diagnostic reports generic. Do not include private game names,
  source, ROMs, screenshots or identifying project details.
