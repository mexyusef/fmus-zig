const std = @import("std");
const time = @import("time.zig");

pub const Controller = struct {
    active: bool = false,
    started_ms: ?i64 = null,
    keepalive_interval_ms: u32 = 3_000,
    ttl_ms: u32 = 60_000,

    pub fn start(self: *Controller) void {
        self.active = true;
        self.started_ms = time.nowMs();
    }

    pub fn stop(self: *Controller) void {
        self.active = false;
    }

    pub fn expired(self: *const Controller, now_ms: i64) bool {
        if (!self.active) return false;
        const started = self.started_ms orelse return false;
        return now_ms - started >= self.ttl_ms;
    }
};

test "typing controller expires after ttl" {
    var c: Controller = .{ .ttl_ms = 10 };
    c.start();
    try std.testing.expect(c.expired((c.started_ms orelse 0) + 11));
}
