const std = @import("std");
const time = @import("time.zig");

pub const Backoff = struct {
    base_ms: u64 = 250,
    max_ms: u64 = 5_000,
    factor: u8 = 2,

    pub fn delay(self: Backoff, attempt: usize) u64 {
        var delay_ms = self.base_ms;
        var i: usize = 0;
        while (i < attempt) : (i += 1) {
            if (delay_ms >= self.max_ms) return self.max_ms;
            const next = delay_ms * self.factor;
            delay_ms = if (next > self.max_ms) self.max_ms else next;
        }
        return delay_ms;
    }

    pub fn wait(self: Backoff, attempt: usize) void {
        time.sleepMs(self.delay(attempt));
    }
};

test "backoff caps at max" {
    const b: Backoff = .{ .base_ms = 100, .max_ms = 500, .factor = 2 };
    try std.testing.expectEqual(@as(u64, 100), b.delay(0));
    try std.testing.expectEqual(@as(u64, 200), b.delay(1));
    try std.testing.expectEqual(@as(u64, 500), b.delay(4));
}
