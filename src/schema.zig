const std = @import("std");

pub fn Versioned(comptime T: type) type {
    return struct {
        version: u32,
        data: T,
    };
}

pub fn wrap(comptime T: type, version: u32, value: T) Versioned(T) {
    return .{ .version = version, .data = value };
}

pub fn migrate(comptime A: type, comptime B: type, versioned: Versioned(A), comptime f: fn (A) B) Versioned(B) {
    return .{
        .version = versioned.version + 1,
        .data = f(versioned.data),
    };
}

test "schema wrap stores version" {
    const doc = wrap(struct { name: []const u8 }, 1, .{ .name = "zig" });
    try std.testing.expectEqual(@as(u32, 1), doc.version);
}
