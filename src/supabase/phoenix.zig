const std = @import("std");
const root = @import("root");
const json = if (@hasDecl(root, "json")) root.json else @import("../json.zig");

pub const Message = struct {
    topic: []const u8,
    event: []const u8,
    payload: std.json.Value,
    ref: ?[]const u8 = null,
    join_ref: ?[]const u8 = null,
};

pub const AccessTokenPayload = struct {
    config: struct {
        broadcast: struct { ack: bool = false, self: bool = false } = .{},
        presence: struct { enabled: bool = false } = .{},
        postgres_changes: []const std.json.Value = &.{},
        private: bool = false,
    } = .{},
    access_token: ?[]const u8 = null,
};

pub fn encodeAlloc(allocator: std.mem.Allocator, topic: []const u8, event: []const u8, payload: anytype, ref: ?[]const u8, join_ref: ?[]const u8) ![]u8 {
    return try json.stringifyAlloc(allocator, .{
        .topic = topic,
        .event = event,
        .payload = payload,
        .ref = ref,
        .join_ref = join_ref,
    });
}

pub fn decode(allocator: std.mem.Allocator, input: []const u8) !Message {
    return try json.parse(allocator, Message, input);
}

test "phoenix encode and decode roundtrip" {
    const alloc = std.testing.allocator;
    const encoded = try encodeAlloc(alloc, "realtime:public:todos", "phx_join", .{ .access_token = "at" }, "1", "1");
    defer alloc.free(encoded);

    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const decoded = try decode(arena_state.allocator(), encoded);
    try std.testing.expectEqualStrings("phx_join", decoded.event);
    try std.testing.expectEqualStrings("1", decoded.ref.?);
}
