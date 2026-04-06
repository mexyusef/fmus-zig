const std = @import("std");
const safeeq = @import("safeeq.zig");

pub const Payload = struct {
    path: []const u8,
    body: []const u8,
    signature: ?[]const u8 = null,
};

pub fn verify(secret_value: []const u8, provided: ?[]const u8) bool {
    const sig = provided orelse return false;
    return safeeq.bytes(secret_value, sig);
}

test "webhook verify compares signatures" {
    try std.testing.expect(verify("abc", "abc"));
    try std.testing.expect(!verify("abc", "def"));
}
