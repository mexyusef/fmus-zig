const std = @import("std");

pub fn bytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    for (a, b) |lhs, rhs| diff |= lhs ^ rhs;
    return diff == 0;
}

test "safe bytes compare works" {
    try std.testing.expect(bytes("abc", "abc"));
    try std.testing.expect(!bytes("abc", "abd"));
}
