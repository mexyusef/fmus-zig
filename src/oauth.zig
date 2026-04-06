const std = @import("std");

pub const TokenSet = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    expires_at_ms: ?i64 = null,
    token_type: []const u8 = "Bearer",
    scope: ?[]const u8 = null,
};

pub const DeviceFlow = struct {
    verification_uri: []const u8,
    user_code: []const u8,
    device_code: []const u8,
    interval_sec: u32 = 5,
    expires_in_sec: u32 = 600,
};

pub fn isExpired(tokens: TokenSet, now_ms: i64) bool {
    const expires = tokens.expires_at_ms orelse return false;
    return now_ms >= expires;
}

test "oauth expiry check" {
    try std.testing.expect(isExpired(.{ .access_token = "x", .expires_at_ms = 10 }, 11));
}
