# fmus-zig

`fmus-zig` is a Zig foundation library for developer tools, terminal apps, automation runtimes, websocket services, and agent-oriented software.

Open-source home: `https://github.com/mexyusef/fmus-zig`

## Status

This project is experimental but already usable. The module surface is broad and still evolving, so expect API changes while the foundations are being consolidated.

## Highlights

- General-purpose utility modules for filesystem, path, text, JSON, HTTP, env, config, CLI, process, git, time, logging, retry, queue, job, and daemon workflows
- Developer-runtime modules for tools, agents, plugins, sessions, policy, command routing, audit, transport, RPC, webhook, gateway, and streaming flows
- Windows-native terminal foundations with PTY, parser/state/renderer/runtime/window primitives
- Terminal automation foundations with websocket, HTTP, and GraphQL adapters
- Websocket foundations for client, server, framing, handshake, and message/session flows

## Terminal Foundation Surface

The `fmus.terminal` package now includes:

- terminal parser, state, grid, dirty tracking, ring/reflow, publish, and renderer layers
- Windows runtime and native window primitives
- toolbar, overlays, copy mode, theme presets, fullscreen, zen mode, and screenshot support
- terminal automation primitives for:
  - visible text
  - scrollback text
  - visible buffer
  - scrollback buffer
  - input log
  - command history
  - shell state
  - last command
  - last exit code
- transport adapters for:
  - websocket
  - HTTP
  - GraphQL

## Project Layout

- `src/` library modules
- `examples/` executable demos
- `docs/` notes and documentation

## Requirements

- Zig `0.15.2`

## Build And Test

```powershell
zig test src\fmus.zig
zig build --summary all
```

## Example Binaries

Important examples currently built by `zig build` include:

- `fmus-core-demo`
- `fmus-workflow-demo`
- `fmus-agent-demo`
- `fmus-terminal-demo`
- `fmus-terminal-automation-demo`
- `fmus-terminal-automation-repl`
- `fmus-terminal-visible-automation-demo`
- `fmus-terminal-visible-automation-repl`
- `fmus-terminal-automation-ws-server-demo`
- `fmus-terminal-automation-ws-client-demo`
- `fmus-ws-echo-server-demo`
- `fmus-ws-echo-client-demo`
- `fmus-zigsaw-foundation-demo`
- `fmus-zigsaw-runtime-demo`
- `fmus-zigsaw-platform-demo`

## Use As A Local Dependency

```zig
.dependencies = .{
    .fmus = .{
        .path = "../fmus-zig",
    },
},
```

Then import `fmus` from your build script and Zig source as needed.

## Notes

- `.fmus-terminal.json` is local runtime state and is intentionally ignored.

## License

MIT. See [LICENSE](LICENSE).
