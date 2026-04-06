const std = @import("std");
const auth = @import("auth.zig");
const secret = @import("secret.zig");

pub const Material = struct {
    profile: auth.Profile,
    value: []const u8,
};

pub fn resolve(allocator: std.mem.Allocator, profile: auth.Profile, env_key: ?[]const u8, file_path: ?[]const u8) !?Material {
    const value = try secret.getOrFile(allocator, env_key orelse return null, file_path);
    return if (value) |v| .{ .profile = profile, .value = v } else null;
}

test "credential resolve returns null without env key" {
    try std.testing.expectEqual(@as(?Material, null), try resolve(std.testing.allocator, .{
        .id = "p",
        .provider = "demo",
        .mode = .api_key,
    }, null, null));
}
