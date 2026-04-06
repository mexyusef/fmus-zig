const std = @import("std");
const fs = @import("fs.zig");
const json = @import("json.zig");

pub fn JsonStore(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        path: []const u8,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, path: []const u8) Self {
            return .{ .allocator = allocator, .path = path };
        }

        pub fn load(self: Self) !?T {
            if (!fs.exists(self.path)) return null;
            return try json.parseFile(self.allocator, T, self.path);
        }

        pub fn save(self: Self, value: T) !void {
            try fs.writeJson(self.path, value);
        }
    };
}

test "json store saves and loads" {
    const path = "__fmus_store_test.json";
    defer fs.remove(path) catch {};
    const Store = JsonStore(struct { name: []const u8 });
    const store = Store.init(std.heap.page_allocator, path);
    try store.save(.{ .name = "zig" });
    const loaded = (try store.load()).?;
    try std.testing.expectEqualStrings("zig", loaded.name);
}
