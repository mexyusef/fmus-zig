# Supabase + Ziggy Notes

These notes capture API choices in `fmus-zig` that make a future `ziggy`-based Supabase client easier to build.

## UI-Oriented SDK Principles

- Prefer plain row structs and slices over callback-heavy result wrappers.
- Keep `rest.rpcParse(T, ...)` and `query_builder.jsonParse(T)` available so TUI code can decode directly into list or table row models.
- Support composable search filters such as `orRaw(...)` so search boxes can project directly into query state.
- Keep keepalive/report outputs as plain structs that can be rendered in a `ziggy.Table`, `ziggy.List`, or `ziggy.StaticLog`.

## Likely Ziggy Bindings

- `ziggy.List` for document search hits
- `ziggy.Table` for bucket listings, keepalive probes, and document metadata
- `ziggy.Document` or `ziggy.RichDocument` for previewing document content/snippets
- `ziggy.Input` or `ziggy.TextInput` for search query entry
- `ziggy.StatusBar` for project URL, auth mode, and refresh status
- `ziggy.Toast` or `ziggy.NoticeBar` for request errors

## Suggested Future Screens

- Project switcher and auth mode selector
- Search view for `sidoarch__documents`
- Bucket/file browser for storage
- Realtime monitor for presence and broadcast diagnostics
- Keepalive dashboard with last run status and next scheduled run

## Windows Output Rule

- `fmus-zig` examples that render `ziggy` UI should always call `ziggy.prepareConsole()`
- Rendered output should leave the process through `ziggy.writeStdout(...)` or a `ziggy.Program` with `Tty.output_file`
- Avoid direct `stdout.writeAll(...)` for terminal UI snapshots on Windows
