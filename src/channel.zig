const std = @import("std");
const msg = @import("msg.zig");
const contact = @import("contact.zig");

pub const Caps = struct {
    supports_threads: bool = false,
    supports_typing: bool = false,
    supports_edit: bool = false,
    supports_delete: bool = false,
    supports_media: bool = true,
};

pub const EventKind = enum {
    message,
    delivery,
    presence,
    typing,
    @"error",
};

pub const Event = struct {
    kind: EventKind,
    channel: contact.ChannelKind,
    message: ?msg.Message = null,
    note: ?[]const u8 = null,
};

pub const Outbound = struct {
    channel: contact.ChannelKind,
    to: contact.Contact,
    text: []const u8,
    thread_id: ?[]const u8 = null,
};

test "channel event stores kind" {
    const evt: Event = .{ .kind = .typing, .channel = .slack };
    try std.testing.expectEqual(EventKind.typing, evt.kind);
}
