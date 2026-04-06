const std = @import("std");
const time = @import("time.zig");

pub const State = enum {
    offline,
    online,
    busy,
    idle,
};

pub const Snapshot = struct {
    state: State,
    updated_ms: i64,
};

pub fn set(state: State) Snapshot {
    return .{ .state = state, .updated_ms = time.nowMs() };
}

test "presence set timestamps state" {
    try std.testing.expectEqual(State.online, set(.online).state);
}
