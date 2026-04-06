const std = @import("std");

pub fn redactMiddle(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len <= 8) return try allocator.dupe(u8, "***");
    return try std.fmt.allocPrint(allocator, "{s}...{s}", .{ input[0..4], input[input.len - 4 ..] });
}

pub fn clampSecretForLog(input: []const u8) []const u8 {
    return if (input.len == 0) "<empty>" else "<redacted>";
}

test "redact middle keeps ends" {
    const alloc = std.testing.allocator;
    const out = try redactMiddle(alloc, "abcdefghijkl");
    defer alloc.free(out);
    try std.testing.expect(std.mem.startsWith(u8, out, "abcd"));
}
