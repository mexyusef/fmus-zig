# Contributing

Small, focused pull requests are preferred.

## Development

```powershell
zig build test
zig fmt src examples build.zig
```

## Guidelines

- Keep public APIs coherent and documented through examples or README notes.
- Add or update tests when behavior changes.
- Avoid mixing broad refactors with feature work in one pull request.
- Keep platform-specific behavior explicit, especially for Windows console handling and filesystem paths.

## Issues

Use GitHub issues for bugs, API gaps, and documentation problems. Include the Zig version, platform, and a minimal reproduction when possible.
