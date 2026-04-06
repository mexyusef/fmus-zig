const std = @import("std");
const time = @import("time.zig");

pub fn hex(allocator: std.mem.Allocator, bytes_len: usize) ![]u8 {
    const bytes = try allocator.alloc(u8, bytes_len);
    defer allocator.free(bytes);
    std.crypto.random.bytes(bytes);
    const alphabet = "0123456789abcdef";
    const out = try allocator.alloc(u8, bytes_len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = alphabet[(b >> 4) & 0x0f];
        out[i * 2 + 1] = alphabet[b & 0x0f];
    }
    return out;
}

pub fn prefixed(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    const rand = try hex(allocator, 8);
    defer allocator.free(rand);
    return try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, rand });
}

pub fn stamped(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    const rand = try hex(allocator, 4);
    defer allocator.free(rand);
    return try std.fmt.allocPrint(allocator, "{s}_{d}_{s}", .{ prefix, time.nowMs(), rand });
}

test "prefixed id starts with prefix" {
    const alloc = std.testing.allocator;
    const out = try prefixed(alloc, "job");
    defer alloc.free(out);
    try std.testing.expect(std.mem.startsWith(u8, out, "job_"));
}
