# Supabase Ziggy Demo

This example shows how `fmus-zig` and the local sibling `ziggy` repo can be composed into a TUI-oriented Supabase client.

## Local Dependency

The build only adds the demo when `..\ziggy\src\ziggy.zig` exists.

Build and run:

```powershell
zig build example-supabase-ziggy
zig build run-supabase-ziggy-demo -- python
zig build example-supabase-ziggy-interactive
zig build run-supabase-ziggy-interactive-demo
```

The demo loads Supabase credentials from `..\ .env`, calls the live `search_documents` RPC, and renders:

- a command-surface panel that previews the future query workflow
- a result table for matching documents
- a preview pane for the first result
- a status/header shell that can later map cleanly to an interactive `ziggy.Program`

On Windows, the demo now uses `ziggy.prepareConsole()` plus `ziggy.writeStdout(...)` so box drawing and mixed ANSI/Unicode output go through the fixed `ziggy` console path instead of raw stdout bytes.

The interactive variant uses `ziggy.Program` with the same live Supabase backend:

- edit the query in-place
- press `Enter` to run a new search
- use arrow keys to change the focused result
- read the preview pane live

## Why This Matters

This is the bridge between:

- `fmus-zig` as the network/data SDK
- `ziggy` as the terminal UI layer

The example intentionally keeps the SDK surface typed and row-oriented so later interactive views can reuse the same parsed models for:

- tables
- lists
- preview panes
- command palette driven search flows
