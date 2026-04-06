const std = @import("std");
const fs = @import("fs.zig");
const json = @import("json.zig");

pub fn loadJson(allocator: std.mem.Allocator, comptime T: type, path: []const u8) !T {
    return try json.parseFile(allocator, T, path);
}

pub fn loadJsonOr(allocator: std.mem.Allocator, comptime T: type, path: []const u8, fallback: T) !T {
    if (!fs.exists(path)) return fallback;
    return try loadJson(allocator, T, path);
}

pub fn saveJson(path: []const u8, value: anytype) !void {
    return try fs.writeJson(path, value);
}

pub fn maybeLoadJson(allocator: std.mem.Allocator, comptime T: type, path: []const u8) !?T {
    if (!fs.exists(path)) return null;
    return try loadJson(allocator, T, path);
}

test "load json or returns fallback for missing file" {
    const Config = struct {
        port: u16,
    };
    const cfg = try loadJsonOr(std.testing.allocator, Config, "__fmus_missing_cfg__.json", .{ .port = 8080 });
    try std.testing.expectEqual(@as(u16, 8080), cfg.port);
}
