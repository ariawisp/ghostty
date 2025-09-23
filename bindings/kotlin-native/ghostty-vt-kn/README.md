# Ghostty VT Kotlin/Native Binding (macOS Apple Silicon)

This is a minimal Kotlin/Native binding to Ghostty's VT engine C API.

- Target: macOS 26, Apple Silicon (arm64)
- Build flow:
  1. From the Ghostty repo root, run `zig build` (produces `zig-out/include` and `zig-out/lib`).
  2. From this directory, run Gradle tasks as needed (e.g., `:build`).

The cinterop def links against `zig-out/lib/libghostty_vt_c.a` and includes headers from `zig-out/include`.

The `org.ghostty.vt` package exposes a thin, allocation-conscious wrapper with:
- Session lifecycle and I/O
- Dirty span + per-row readback (arena-based)
- Scrollback readback
- Hyperlink URI queries (grid and scrollback)
- Event callbacks (title, clipboard, bell)
- Mode queries (bracketed paste, mouse modes, kitty flags)

See `src/macosArm64Main/kotlin/org/ghostty/vt/GhosttyVt.kt` for the API.
