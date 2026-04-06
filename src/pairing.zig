const std = @import("std");
const id = @import("id.zig");
const time = @import("time.zig");

pub const Request = struct {
    code: []const u8,
    channel: []const u8,
    sender: []const u8,
    created_ms: i64,
    approved: bool = false,
};

pub fn create(allocator: std.mem.Allocator, channel: []const u8, sender: []const u8) !Request {
    return .{
        .code = try id.hex(allocator, 3),
        .channel = channel,
        .sender = sender,
        .created_ms = time.nowMs(),
    };
}

pub fn approve(req: *Request) void {
    req.approved = true;
}

test "pairing request approves" {
    const alloc = std.testing.allocator;
    var req = try create(alloc, "discord", "u1");
    defer alloc.free(req.code);
    approve(&req);
    try std.testing.expect(req.approved);
}
