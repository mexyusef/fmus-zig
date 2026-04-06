const std = @import("std");

pub fn Queue(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        items: std.ArrayListUnmanaged(T) = .empty,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        pub fn push(self: *Self, value: T) !void {
            try self.items.append(self.allocator, value);
        }

        pub fn len(self: *const Self) usize {
            return self.items.items.len;
        }

        pub fn empty(self: *const Self) bool {
            return self.items.items.len == 0;
        }

        pub fn peek(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        pub fn pop(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            const first = self.items.items[0];
            if (self.items.items.len > 1) {
                std.mem.copyForwards(T, self.items.items[0 .. self.items.items.len - 1], self.items.items[1..]);
            }
            self.items.items.len -= 1;
            return first;
        }
    };
}

test "queue push and pop" {
    var q = Queue(i32).init(std.testing.allocator);
    defer q.deinit();
    try q.push(1);
    try q.push(2);
    try std.testing.expectEqual(@as(?i32, 1), q.pop());
    try std.testing.expectEqual(@as(?i32, 2), q.pop());
    try std.testing.expectEqual(@as(?i32, null), q.pop());
}
