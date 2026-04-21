const std = @import("std");

pub const User = struct {
    id: []const u8,
    email: ?[]const u8 = null,
    role: ?[]const u8 = null,
};

pub const Session = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    token_type: []const u8 = "bearer",
    expires_at_ms: ?i64 = null,
    user: ?User = null,
};

pub fn isExpired(session: Session, now_ms: i64) bool {
    const expires_at = session.expires_at_ms orelse return false;
    return now_ms >= expires_at;
}

pub fn clone(allocator: std.mem.Allocator, session: Session) !Session {
    return .{
        .access_token = try allocator.dupe(u8, session.access_token),
        .refresh_token = if (session.refresh_token) |value| try allocator.dupe(u8, value) else null,
        .token_type = try allocator.dupe(u8, session.token_type),
        .expires_at_ms = session.expires_at_ms,
        .user = if (session.user) |user| try cloneUser(allocator, user) else null,
    };
}

pub fn deinit(allocator: std.mem.Allocator, session: *Session) void {
    allocator.free(session.access_token);
    if (session.refresh_token) |value| allocator.free(value);
    allocator.free(session.token_type);
    if (session.user) |*user| deinitUser(allocator, user);
}

pub fn cloneUser(allocator: std.mem.Allocator, user: User) !User {
    return .{
        .id = try allocator.dupe(u8, user.id),
        .email = if (user.email) |value| try allocator.dupe(u8, value) else null,
        .role = if (user.role) |value| try allocator.dupe(u8, value) else null,
    };
}

pub fn deinitUser(allocator: std.mem.Allocator, user: *User) void {
    allocator.free(user.id);
    if (user.email) |value| allocator.free(value);
    if (user.role) |value| allocator.free(value);
}

test "session expiry check" {
    try std.testing.expect(isExpired(.{
        .access_token = "token",
        .expires_at_ms = 42,
    }, 42));
}

test "session clone duplicates values" {
    const alloc = std.testing.allocator;
    var session = try clone(alloc, .{
        .access_token = "a",
        .refresh_token = "r",
        .token_type = "bearer",
        .user = .{ .id = "u1", .email = "u@example.com" },
    });
    defer deinit(alloc, &session);

    try std.testing.expectEqualStrings("a", session.access_token);
    try std.testing.expectEqualStrings("u1", session.user.?.id);
}
