const std = @import("std");

pub const SpawnConfig = struct {
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
    rows: u16 = 24,
    cols: u16 = 80,
};

pub const ReadChunk = struct {
    bytes: []const u8,
    owned: bool = false,
};

pub const Pty = struct {
    pub fn spawn(_: std.mem.Allocator, _: SpawnConfig) !Pty {
        return error.UnsupportedPlatform;
    }

    pub fn deinit(_: *Pty) void {}

    pub fn readAvailable(_: *Pty, _: std.mem.Allocator) !?ReadChunk {
        return error.UnsupportedPlatform;
    }

    pub fn writeAll(_: *Pty, _: []const u8) !void {
        return error.UnsupportedPlatform;
    }

    pub fn resize(_: *Pty, _: u16, _: u16) !void {
        return error.UnsupportedPlatform;
    }

    pub fn childExited(_: *Pty) bool {
        return true;
    }

    pub fn exitCode(_: *Pty) ?u8 {
        return null;
    }

    pub fn wait(_: *Pty) void {}
};
