const std = @import("std");

pub const Kind = enum {
    text,
    thinking,
    tool_call,
    tool_result,
    progress,
    notice,
    done,
    err,
};

pub const Event = struct {
    kind: Kind,
    text: ?[]const u8 = null,
    name: ?[]const u8 = null,
    progress: ?f32 = null,
};

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(Event) = .empty,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Buffer) void {
        for (self.items.items) |evt| {
            if (evt.text) |v| self.allocator.free(v);
            if (evt.name) |v| self.allocator.free(v);
        }
        self.items.deinit(self.allocator);
    }

    pub fn push(self: *Buffer, evt: Event) !void {
        try self.items.append(self.allocator, .{
            .kind = evt.kind,
            .text = if (evt.text) |v| try self.allocator.dupe(u8, v) else null,
            .name = if (evt.name) |v| try self.allocator.dupe(u8, v) else null,
            .progress = evt.progress,
        });
    }

    pub fn len(self: *const Buffer) usize {
        return self.items.items.len;
    }
};

test "stream buffer stores events" {
    var buf = Buffer.init(std.testing.allocator);
    defer buf.deinit();
    try buf.push(.{ .kind = .text, .text = "hello" });
    try std.testing.expectEqual(@as(usize, 1), buf.len());
}
