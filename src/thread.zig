const std = @import("std");

pub const Binding = struct {
    channel: []const u8,
    conversation_id: []const u8,
    thread_id: []const u8,
};

pub fn bindingId(allocator: std.mem.Allocator, binding: Binding) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{
        binding.channel,
        binding.conversation_id,
        binding.thread_id,
    });
}

test "binding id formats consistently" {
    const alloc = std.testing.allocator;
    const out = try bindingId(alloc, .{ .channel = "slack", .conversation_id = "c1", .thread_id = "t1" });
    defer alloc.free(out);
    try std.testing.expectEqualStrings("slack:c1:t1", out);
}
