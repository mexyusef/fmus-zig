const std = @import("std");

pub const Compatibility = struct {
    plugin_api_range: ?[]const u8 = null,
    built_with_host_version: ?[]const u8 = null,
    plugin_sdk_version: ?[]const u8 = null,
    min_gateway_version: ?[]const u8 = null,
};

pub const Issue = struct {
    field_path: []const u8,
    message: []const u8,
};

pub const Validation = struct {
    compatibility: Compatibility = .{},
    issues: []const Issue = &.{},
};

pub fn validate(allocator: std.mem.Allocator, compat: Compatibility) !Validation {
    var issues = std.ArrayList(Issue).empty;
    defer issues.deinit(allocator);
    if (compat.plugin_api_range == null) {
        try issues.append(allocator, .{
            .field_path = "plugin.compat.pluginApi",
            .message = "plugin API range is required",
        });
    }
    if (compat.built_with_host_version == null) {
        try issues.append(allocator, .{
            .field_path = "plugin.build.hostVersion",
            .message = "built-with host version is required",
        });
    }
    return .{
        .compatibility = compat,
        .issues = try issues.toOwnedSlice(allocator),
    };
}

test "plugin contract flags missing fields" {
    const v = try validate(std.testing.allocator, .{});
    defer std.testing.allocator.free(v.issues);
    try std.testing.expect(v.issues.len >= 1);
}
