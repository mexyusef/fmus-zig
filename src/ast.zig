const std = @import("std");

pub const Node = struct {
    tag: []const u8,
    text: ?[]const u8 = null,
    children: std.ArrayListUnmanaged(Node) = .empty,

    pub fn init(allocator: std.mem.Allocator, tag: []const u8) !Node {
        return .{
            .tag = try allocator.dupe(u8, tag),
        };
    }

    pub fn withText(allocator: std.mem.Allocator, tag: []const u8, text: []const u8) !Node {
        return .{
            .tag = try allocator.dupe(u8, tag),
            .text = try allocator.dupe(u8, text),
        };
    }

    pub fn add(self: *Node, allocator: std.mem.Allocator, child: Node) !void {
        try self.children.append(allocator, child);
    }

    pub fn visit(self: *const Node, visitor: anytype) !void {
        try visitor(self);
        for (self.children.items) |*child| {
            try child.visit(visitor);
        }
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.tag);
        if (self.text) |txt| allocator.free(txt);
        for (self.children.items) |*child| child.deinit(allocator);
        self.children.deinit(allocator);
    }
};

test "ast node stores children" {
    const alloc = std.testing.allocator;
    var root = try Node.init(alloc, "root");
    defer root.deinit(alloc);
    try root.add(alloc, try Node.withText(alloc, "name", "zig"));
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
}
