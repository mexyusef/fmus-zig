const std = @import("std");
const fs = @import("fs.zig");
const json = @import("json.zig");

pub const Manifest = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    entry: ?[]const u8 = null,
    permissions: []const []const u8 = &.{},
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Manifest {
    return try json.parseFile(allocator, Manifest, path);
}

pub fn exists(path: []const u8) bool {
    return fs.exists(path);
}

test "skill manifest shape compiles" {
    const m: Manifest = .{
        .name = "demo",
        .version = "0.1.0",
        .description = "Demo skill",
    };
    try std.testing.expectEqualStrings("demo", m.name);
}
