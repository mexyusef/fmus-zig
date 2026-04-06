const std = @import("std");

pub const Policy = enum {
    open,
    mentions_only,
    replies_only,
    closed,
};

pub fn allows(policy: Policy, mentioned: bool, replied: bool) bool {
    return switch (policy) {
        .open => true,
        .mentions_only => mentioned,
        .replies_only => replied,
        .closed => false,
    };
}

test "group policy allows mentions" {
    try std.testing.expect(allows(.mentions_only, true, false));
}
