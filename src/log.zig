const std = @import("std");
const time = @import("time.zig");

pub const Level = enum {
    debug,
    info,
    warn,
    err,

    pub fn tag(self: Level) []const u8 {
        return switch (self) {
            .debug => "DBG",
            .info => "INF",
            .warn => "WRN",
            .err => "ERR",
        };
    }
};

pub fn write(writer: *std.Io.Writer, level: Level, scope: []const u8, message: []const u8) !void {
    try writer.print("[{d}] {s} {s}: {s}\n", .{ time.nowSec(), level.tag(), scope, message });
}

pub fn info(writer: *std.Io.Writer, scope: []const u8, message: []const u8) !void {
    try write(writer, .info, scope, message);
}

test "level tags are stable" {
    try std.testing.expectEqualStrings("INF", Level.info.tag());
}
