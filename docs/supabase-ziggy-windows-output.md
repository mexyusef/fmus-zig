# Supabase Ziggy Windows Output

`fmus-zig` should not write rendered `ziggy` output directly to `stdout` on Windows.

Use:

- `ziggy.prepareConsole()`
- `ziggy.writeStdout(...)`
- `ziggy.writeStderr(...)`

This matters because `ziggy` now distinguishes between:

- real console handles
- pipes and file redirection

For real Windows consoles, `ziggy` converts UTF-8 text spans to UTF-16 and writes them through `WriteConsoleW`, while preserving ANSI escape sequences as raw bytes. That is the correct boundary for avoiding mojibake from box-drawing glyphs, spinners, and mixed ANSI + Unicode output.

## Rule For Future TUI Apps

- Interactive `ziggy.Program` apps should attach the real stdout file to `Tty.output_file`
- Static screen snapshots should render to a string and then use `ziggy.writeStdout(...)`
- Do not bypass this path with manual `stdout.writeAll(...)` for terminal UI output on Windows

## Supabase TUI Implication

The future `fmus-zig` + `ziggy` Supabase client should keep:

- network and parsing in `fmus-zig`
- terminal rendering and output ownership in `ziggy`

That keeps the SDK portable while letting the TUI layer own platform-specific terminal correctness.
