const std = @import("std");
const env = @import("env.zig");
const fs = @import("fs.zig");

pub fn getOrFile(allocator: std.mem.Allocator, env_key: []const u8, file_path: ?[]const u8) !?[]u8 {
    if (try env.get(allocator, env_key)) |value| return value;
    if (file_path) |path| {
        if (!fs.exists(path)) return null;
        return try fs.readText(allocator, path);
    }
    return null;
}

pub fn redact(input: []const u8) []const u8 {
    if (input.len <= 8) return "***";
    return input[0..4];
}

test "redact short values" {
    try std.testing.expectEqualStrings("***", redact("secret"));
}
