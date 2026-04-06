const std = @import("std");
const time = @import("time.zig");

pub const Status = struct {
    active_runs: usize = 0,
    busy: bool = false,
    last_activity_ms: ?i64 = null,
};

pub const Machine = struct {
    status: Status = .{},

    pub fn onStart(self: *Machine) void {
        self.status.active_runs += 1;
        self.status.busy = self.status.active_runs > 0;
        self.status.last_activity_ms = time.nowMs();
    }

    pub fn onEnd(self: *Machine) void {
        self.status.active_runs = if (self.status.active_runs == 0) 0 else self.status.active_runs - 1;
        self.status.busy = self.status.active_runs > 0;
        self.status.last_activity_ms = time.nowMs();
    }
};

test "runstate machine tracks active runs" {
    var m: Machine = .{};
    m.onStart();
    m.onEnd();
    try std.testing.expectEqual(@as(usize, 0), m.status.active_runs);
}
