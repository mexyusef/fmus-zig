const std = @import("std");
const time = @import("time.zig");

pub const Kind = enum {
    gateway_started,
    gateway_stopped,
    inbound_message,
    outbound_message,
    tool_call,
    tool_result,
    channel_error,
    policy_denied,
    job_run,
    notice,
};

pub const Event = struct {
    kind: Kind,
    ts_ms: i64 = 0,
    source: []const u8,
    detail: []const u8,

    pub fn init(kind: Kind, source: []const u8, detail: []const u8) Event {
        return .{
            .kind = kind,
            .ts_ms = time.nowMs(),
            .source = source,
            .detail = detail,
        };
    }
};

test "event init sets source" {
    const evt = Event.init(.notice, "demo", "ok");
    try std.testing.expectEqualStrings("demo", evt.source);
}
