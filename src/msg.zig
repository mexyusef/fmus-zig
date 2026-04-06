const std = @import("std");
const contact = @import("contact.zig");
const media = @import("media.zig");
const time = @import("time.zig");

pub const Id = struct {
    value: []const u8,
};

pub const Message = struct {
    id: Id,
    channel: contact.ChannelKind,
    from: contact.Contact,
    to: ?contact.Contact = null,
    text: ?[]const u8 = null,
    media_items: []const media.Ref = &.{},
    thread_id: ?[]const u8 = null,
    created_ms: i64 = 0,

    pub fn init(id_value: []const u8, channel: contact.ChannelKind, from: contact.Contact) Message {
        return .{
            .id = .{ .value = id_value },
            .channel = channel,
            .from = from,
            .created_ms = time.nowMs(),
        };
    }
};

test "message init sets id" {
    const from: contact.Contact = .{ .id = .{ .channel = .discord, .value = "u1" } };
    const msg = Message.init("m1", .discord, from);
    try std.testing.expectEqualStrings("m1", msg.id.value);
}
