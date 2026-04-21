# Supabase Keepalive

The `fmus.supabase.keepalive` module provides low-cost probes suitable for a daily scheduled run against a Supabase project.

Current default plan:

- `auth-settings`
- `storage-buckets`

Default schedule:

- `17 9 * * *`

This is exposed as:

- `fmus.supabase.keepalive.Plan.freeTierDaily()`

## Intended Usage

- Load config from process env or `.env`
- Run the keepalive plan once per day
- Record/report success status

## Windows Scheduling

Example command:

```powershell
zig run .\supabase_keepalive_standalone.zig
```

Suggested Task Scheduler trigger:

- Daily
- Run whether user is logged in or not if desired
- Start in: `C:\github-sido\zigs\fmus-zig`

Suggested action:

```powershell
powershell.exe -NoProfile -Command "cd C:\github-sido\zigs\fmus-zig; zig run .\supabase_keepalive_standalone.zig"
```
