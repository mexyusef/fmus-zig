const std = @import("std");
const channel = @import("channel.zig");

pub const Method = struct {
    name: []const u8,
    description: []const u8,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    methods: std.ArrayListUnmanaged(Method) = .empty,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        self.methods.deinit(self.allocator);
    }

    pub fn add(self: *Registry, method: Method) !void {
        try self.methods.append(self.allocator, method);
    }

    pub fn has(self: *const Registry, name: []const u8) bool {
        for (self.methods.items) |method| {
            if (std.mem.eql(u8, method.name, name)) return true;
        }
        return false;
    }
};

pub const Dispatch = struct {
    method: []const u8,
    event: ?channel.Event = null,
};

test "gateway registry stores methods" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.add(.{ .name = "browser.request", .description = "browser request" });
    try std.testing.expect(reg.has("browser.request"));
}
