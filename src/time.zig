const std = @import("std");

pub fn nowMs() i64 {
    return std.time.milliTimestamp();
}

pub fn nowSec() i64 {
    return @divTrunc(nowMs(), std.time.ms_per_s);
}

pub fn sleepMs(ms: u64) void {
    std.Thread.sleep(ms * std.time.ns_per_ms);
}

pub const Stopwatch = struct {
    started_ms: i64,

    pub fn start() Stopwatch {
        return .{ .started_ms = nowMs() };
    }

    pub fn elapsedMs(self: *const Stopwatch) i64 {
        return nowMs() - self.started_ms;
    }
};

test "stopwatch elapsed is non-negative" {
    const sw = Stopwatch.start();
    try std.testing.expect(sw.elapsedMs() >= 0);
}
