const std = @import("std");
const time = @import("time.zig");

pub const State = enum {
    queued,
    running,
    done,
    failed,
};

pub const Job = struct {
    id: []const u8,
    name: []const u8,
    state: State = .queued,
    created_ms: i64 = 0,
    started_ms: ?i64 = null,
    ended_ms: ?i64 = null,
    error_message: ?[]const u8 = null,

    pub fn init(id: []const u8, name: []const u8) Job {
        return .{
            .id = id,
            .name = name,
            .created_ms = time.nowMs(),
        };
    }

    pub fn start(self: *Job) void {
        self.state = .running;
        self.started_ms = time.nowMs();
    }

    pub fn finish(self: *Job) void {
        self.state = .done;
        self.ended_ms = time.nowMs();
    }

    pub fn fail(self: *Job, message: []const u8) void {
        self.state = .failed;
        self.error_message = message;
        self.ended_ms = time.nowMs();
    }
};

test "job state transitions" {
    var j = Job.init("j1", "demo");
    j.start();
    j.finish();
    try std.testing.expectEqual(State.done, j.state);
}
