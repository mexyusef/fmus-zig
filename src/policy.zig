const std = @import("std");

pub const Mode = enum {
    allow,
    ask,
    deny,
};

pub const Action = enum {
    read,
    write,
    shell,
    network,
    channel_send,
    media_access,
};

pub const Rule = struct {
    action: Action,
    mode: Mode,
};

pub const Decision = struct {
    allowed: bool,
    reason: []const u8,
};

pub fn decide(default_mode: Mode, rules: []const Rule, action: Action) Decision {
    for (rules) |rule| {
        if (rule.action == action) {
            return switch (rule.mode) {
                .allow => .{ .allowed = true, .reason = "explicit allow" },
                .ask => .{ .allowed = false, .reason = "requires approval" },
                .deny => .{ .allowed = false, .reason = "explicit deny" },
            };
        }
    }
    return switch (default_mode) {
        .allow => .{ .allowed = true, .reason = "default allow" },
        .ask => .{ .allowed = false, .reason = "default ask" },
        .deny => .{ .allowed = false, .reason = "default deny" },
    };
}

test "policy rule overrides default" {
    const out = decide(.deny, &.{.{ .action = .network, .mode = .allow }}, .network);
    try std.testing.expect(out.allowed);
}
