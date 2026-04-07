const builtin = @import("builtin");

const impl = switch (builtin.os.tag) {
    .windows => @import("pty_windows.zig"),
    else => @import("pty_stub.zig"),
};

pub const SpawnConfig = impl.SpawnConfig;
pub const ReadChunk = impl.ReadChunk;
pub const Pty = impl.Pty;
pub const ShellType = impl.ShellType;
