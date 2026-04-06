const std = @import("std");

pub const Def = struct {
    name: []const u8,
    description: []const u8,
};

pub const Match = struct {
    def: Def,
    args: []const []const u8,
};

pub fn route(defs: []const Def, argv: []const []const u8) ?Match {
    if (argv.len == 0) return null;
    for (defs) |def| {
        if (std.mem.eql(u8, def.name, argv[0])) {
            return .{ .def = def, .args = if (argv.len > 1) argv[1..] else &.{} };
        }
    }
    return null;
}

test "route finds command" {
    const found = route(&.{.{ .name = "doctor", .description = "run checks" }}, &.{ "doctor", "--fix" }).?;
    try std.testing.expectEqualStrings("doctor", found.def.name);
}
