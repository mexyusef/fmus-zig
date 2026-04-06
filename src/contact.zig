const std = @import("std");

pub const ChannelKind = enum {
    discord,
    whatsapp,
    slack,
    telegram,
    webchat,
    unknown,
};

pub const Id = struct {
    channel: ChannelKind,
    value: []const u8,
};

pub const Contact = struct {
    id: Id,
    display_name: ?[]const u8 = null,
    username: ?[]const u8 = null,
};

test "contact stores channel id" {
    const c: Contact = .{ .id = .{ .channel = .discord, .value = "123" } };
    try std.testing.expectEqual(ChannelKind.discord, c.id.channel);
}
