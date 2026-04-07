const std = @import("std");

pub const Kind = enum {
    text,
    ctrl,
    escape,
};

pub const Entry = struct {
    timestamp_ms: i64,
    kind: Kind,
    payload: []u8,

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
    }
};

pub const Log = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    max_entries: usize = 512,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize) Log {
        return .{ .allocator = allocator, .max_entries = max_entries };
    }

    pub fn deinit(self: *Log) void {
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        self.entries.deinit(self.allocator);
    }

    pub fn append(self: *Log, kind: Kind, payload: []const u8) !void {
        if (self.entries.items.len >= self.max_entries) {
            var old = self.entries.orderedRemove(0);
            old.deinit(self.allocator);
        }
        try self.entries.append(self.allocator, .{
            .timestamp_ms = std.time.milliTimestamp(),
            .kind = kind,
            .payload = try self.allocator.dupe(u8, payload),
        });
    }

    pub fn cloneEntriesAlloc(self: *const Log, allocator: std.mem.Allocator) ![]Entry {
        var out = try allocator.alloc(Entry, self.entries.items.len);
        errdefer allocator.free(out);
        for (self.entries.items, 0..) |entry, i| {
            out[i] = .{
                .timestamp_ms = entry.timestamp_ms,
                .kind = entry.kind,
                .payload = try allocator.dupe(u8, entry.payload),
            };
        }
        return out;
    }
};

test "input log appends entries" {
    var log = Log.init(std.testing.allocator, 4);
    defer log.deinit();
    try log.append(.text, "dir\r");
    const items = try log.cloneEntriesAlloc(std.testing.allocator);
    defer {
        for (items) |*it| it.deinit(std.testing.allocator);
        std.testing.allocator.free(items);
    }
    try std.testing.expectEqual(@as(usize, 1), items.len);
}
