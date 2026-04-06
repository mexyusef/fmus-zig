const std = @import("std");
const provider = @import("provider.zig");

pub const TurnState = struct {
    request_id: ?[]const u8 = null,
    status: []const u8 = "idle",
};

pub const Normalized = struct {
    model: provider.RuntimeModel,
    headers: []const struct { name: []const u8, value: []const u8 } = &.{},
    extra_params_json: ?[]const u8 = null,
};

pub fn normalize(model: provider.RuntimeModel) Normalized {
    return .{ .model = model };
}

test "transport normalize keeps model" {
    const normalized = normalize(.{ .provider = "gemini", .id = "2.5-flash" });
    try std.testing.expectEqualStrings("gemini", normalized.model.provider);
}
