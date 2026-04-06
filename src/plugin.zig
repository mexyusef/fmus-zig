const std = @import("std");
const fs = @import("fs.zig");
const json = @import("json.zig");

pub const Manifest = struct {
    name: []const u8,
    version: []const u8,
    kind: []const u8,
    main: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Manifest {
    return try json.parseFile(allocator, Manifest, path);
}

pub fn discover(allocator: std.mem.Allocator, dir_path: []const u8) ![][]u8 {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();
    var out = std.ArrayList([]u8).empty;
    defer out.deinit(allocator);
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        try out.append(allocator, try allocator.dupe(u8, entry.name));
    }
    return out.toOwnedSlice(allocator);
}

test "plugin manifest shape compiles" {
    const m: Manifest = .{ .name = "demo", .version = "0.1.0", .kind = "channel" };
    try std.testing.expectEqualStrings("channel", m.kind);
}
