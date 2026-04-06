const std = @import("std");

pub const Kind = enum {
    provider,
    channel,
    tool,
    service,
    command,
};

pub const Decl = struct {
    id: []const u8,
    kind: Kind,
    description: []const u8,
    enabled: bool = true,
};

test "capability decl stores kind" {
    const decl: Decl = .{ .id = "discord", .kind = .channel, .description = "Discord channel" };
    try std.testing.expectEqual(Kind.channel, decl.kind);
}
