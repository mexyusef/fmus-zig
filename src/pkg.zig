const std = @import("std");

pub const Ref = struct {
    name: []const u8,
    version: []const u8,
    source: []const u8,
    checksum: ?[]const u8 = null,
};

pub const Compatibility = struct {
    min_zig: []const u8,
    platforms: []const []const u8 = &.{},
};

pub fn id(allocator: std.mem.Allocator, package: Ref) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}@{s}", .{ package.name, package.version });
}

test "package id format" {
    const alloc = std.testing.allocator;
    const out = try id(alloc, .{ .name = "demo", .version = "1.0.0", .source = "git" });
    defer alloc.free(out);
    try std.testing.expectEqualStrings("demo@1.0.0", out);
}
