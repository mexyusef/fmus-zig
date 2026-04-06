const std = @import("std");
const prompt = @import("prompt.zig");

pub const SessionEntry = struct {
    role: []const u8,
    content: []const u8,
};

pub const Policy = struct {
    keep_last_turns: usize = 12,
};

pub fn sanitize(allocator: std.mem.Allocator, messages: []const prompt.Message, policy: Policy) ![]SessionEntry {
    const keep = if (messages.len > policy.keep_last_turns) policy.keep_last_turns else messages.len;
    const start = messages.len - keep;
    const out = try allocator.alloc(SessionEntry, keep);
    for (messages[start..], 0..) |msg, i| {
        out[i] = .{ .role = msg.role.asString(), .content = msg.content };
    }
    return out;
}

test "replay sanitize trims history" {
    const alloc = std.testing.allocator;
    const msgs = [_]prompt.Message{
        prompt.Message.user("a"),
        prompt.Message.user("b"),
        prompt.Message.user("c"),
    };
    const out = try sanitize(alloc, &msgs, .{ .keep_last_turns = 2 });
    defer alloc.free(out);
    try std.testing.expectEqual(@as(usize, 2), out.len);
}
