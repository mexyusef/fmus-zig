const std = @import("std");
const event = @import("event.zig");

pub const Level = enum {
    info,
    warn,
    err,
};

pub const Notice = struct {
    level: Level,
    title: []const u8,
    body: []const u8,

    pub fn asEvent(self: Notice) event.Event {
        return event.Event.init(.notice, self.title, self.body);
    }
};

test "notice converts to event" {
    const notice: Notice = .{ .level = .info, .title = "ready", .body = "gateway ready" };
    const evt = notice.asEvent();
    try std.testing.expectEqual(event.Kind.notice, evt.kind);
}
