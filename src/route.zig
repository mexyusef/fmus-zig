const std = @import("std");

pub const LastDelivery = struct {
    channel: []const u8,
    to: []const u8,
    account_id: ?[]const u8 = null,
    thread_id: ?[]const u8 = null,
};

pub const SessionRoute = struct {
    session_key: []const u8,
    last_delivery: ?LastDelivery = null,
};

pub fn normalizeSessionKey(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, std.mem.trim(u8, key, " \t\r\n"));
    _ = std.ascii.lowerString(out, out);
    return out;
}

test "route normalizes session key" {
    const alloc = std.testing.allocator;
    const out = try normalizeSessionKey(alloc, " Main ");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("main", out);
}
