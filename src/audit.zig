const std = @import("std");
const event = @import("event.zig");

pub const Trail = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(event.Event) = .empty,

    pub fn init(allocator: std.mem.Allocator) Trail {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Trail) void {
        self.items.deinit(self.allocator);
    }

    pub fn append(self: *Trail, evt: event.Event) !void {
        try self.items.append(self.allocator, evt);
    }

    pub fn render(self: *const Trail, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        for (self.items.items, 0..) |evt, i| {
            if (i > 0) try out.append(allocator, '\n');
            try out.writer(allocator).print("[{d}] {s} {s}: {s}", .{
                evt.ts_ms,
                @tagName(evt.kind),
                evt.source,
                evt.detail,
            });
        }
        return out.toOwnedSlice(allocator);
    }
};

test "audit trail renders events" {
    var trail = Trail.init(std.testing.allocator);
    defer trail.deinit();
    try trail.append(event.Event.init(.notice, "demo", "ok"));
    const out = try trail.render(std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "demo") != null);
}
