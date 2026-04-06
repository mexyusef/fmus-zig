const std = @import("std");
const async = @import("async.zig");

pub const Policy = struct {
    attempts: usize = 3,
    backoff: async.Backoff = .{},

    pub fn run(self: Policy, f: anytype) !@typeInfo(@typeInfo(@TypeOf(f)).@"fn".return_type.?).error_union.payload {
        var attempt: usize = 0;
        while (attempt < self.attempts) : (attempt += 1) {
            return f() catch |err| {
                if (attempt + 1 >= self.attempts) return err;
                self.backoff.wait(attempt);
                continue;
            };
        }
        unreachable;
    }
};

test "policy retries until success" {
    const policy: Policy = .{ .attempts = 3, .backoff = .{ .base_ms = 0, .max_ms = 0 } };
    const S = struct {
        var count: usize = 0;

        fn call() !usize {
            count += 1;
            if (count < 3) return error.TryAgain;
            return count;
        }
    };
    const out = try policy.run(S.call);
    try std.testing.expectEqual(@as(usize, 3), out);
}
