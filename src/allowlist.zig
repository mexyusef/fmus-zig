const std = @import("std");

pub fn matches(patterns: []const []const u8, value: []const u8) bool {
    for (patterns) |pattern| {
        if (std.mem.eql(u8, pattern, "*")) return true;
        if (std.mem.eql(u8, pattern, value)) return true;
        if (std.mem.endsWith(u8, pattern, "*")) {
            const prefix = pattern[0 .. pattern.len - 1];
            if (std.mem.startsWith(u8, value, prefix)) return true;
        }
    }
    return false;
}

test "allowlist matches wildcard and prefix" {
    try std.testing.expect(matches(&.{ "discord:*" }, "discord:123"));
    try std.testing.expect(matches(&.{ "*" }, "anything"));
}
