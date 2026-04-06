const std = @import("std");
const text = @import("text.zig");

pub const Field = union(enum) {
    any,
    exact: u8,
};

pub const Expr = struct {
    minute: Field,
    hour: Field,
    day: Field,
    month: Field,
    weekday: Field,

    pub fn matches(self: Expr, dt: DateTime) bool {
        return matchField(self.minute, dt.minute) and
            matchField(self.hour, dt.hour) and
            matchField(self.day, dt.day) and
            matchField(self.month, dt.month) and
            matchField(self.weekday, dt.weekday);
    }
};

pub const DateTime = struct {
    minute: u8,
    hour: u8,
    day: u8,
    month: u8,
    weekday: u8,
};

fn matchField(field: Field, value: u8) bool {
    return switch (field) {
        .any => true,
        .exact => |n| n == value,
    };
}

fn parseField(part: []const u8) !Field {
    if (std.mem.eql(u8, part, "*")) return .any;
    return .{ .exact = try std.fmt.parseInt(u8, part, 10) };
}

pub fn parse(expr: []const u8) !Expr {
    const parts = try text.split(std.heap.page_allocator, text.trim(expr), ' ');
    defer std.heap.page_allocator.free(parts);
    if (parts.len != 5) return error.InvalidCronExpr;
    return .{
        .minute = try parseField(parts[0]),
        .hour = try parseField(parts[1]),
        .day = try parseField(parts[2]),
        .month = try parseField(parts[3]),
        .weekday = try parseField(parts[4]),
    };
}

test "cron parse and match" {
    const expr = try parse("30 8 * * *");
    try std.testing.expect(expr.matches(.{ .minute = 30, .hour = 8, .day = 1, .month = 1, .weekday = 1 }));
    try std.testing.expect(!expr.matches(.{ .minute = 31, .hour = 8, .day = 1, .month = 1, .weekday = 1 }));
}
