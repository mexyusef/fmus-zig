# fmus-zig

`fmus-zig` is a Zig utility library for building developer tools, automation, agent runtimes, and service backends with a broader module surface than the Zig standard library.

Open-source home: `https://github.com/mexyusef/fmus-zig`

## Status

This project is experimental but already contains a large usable module set. Expect API churn while the package surface is being consolidated.

## Highlights

- Filesystem, path, text, JSON, HTTP, env, config, CLI, process, and git helpers
- Parsing, grammar, AST, logging, time, retry, queue, job, and daemon primitives
- LLM, tool, agent, plugin, session, policy, command, and audit building blocks
- Service-oriented modules for events, transport, webhook, RPC, gateway, and runtime flows

## Project Layout

- `src/` library modules
- `examples/` executable demos
- `docs/` design notes and planning material
- `scripts/` local release and maintenance helpers

## Requirements

- Zig `0.15.2`

## Build And Test

```powershell
zig build test
zig build example-core
zig build example-workflow
zig build example-agent
zig build example-zigsaw
zig build example-zigsaw-runtime
zig build example-zigsaw-platform
```

## Use As A Local Dependency

Until tagged releases are published, the simplest setup is a local path dependency:

```zig
.dependencies = .{
    .fmus = .{
        .path = "../fmus-zig",
    },
},
```

Then import the module from your build script and Zig source as needed.

## Included Demos

- `fmus-core-demo`
- `fmus-workflow-demo`
- `fmus-agent-demo`
- `fmus-zigsaw-foundation-demo`
- `fmus-zigsaw-runtime-demo`
- `fmus-zigsaw-platform-demo`

## Related Repositories

- `ziggy`: terminal UI toolkit
- `cirebronx`: terminal coding agent
- `zigsaw`: multi-channel assistant runtime

## License

MIT. See [LICENSE](LICENSE).
