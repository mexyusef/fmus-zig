const std = @import("std");

pub const CommandRecord = struct {
    timestamp_ms: i64,
    text: []u8,

    pub fn deinit(self: *CommandRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

pub const Tracker = struct {
    allocator: std.mem.Allocator,
    current_line: std.ArrayListUnmanaged(u8) = .{},
    history: std.ArrayListUnmanaged(CommandRecord) = .{},
    last_command: ?[]u8 = null,
    last_exit_code: ?u8 = null,
    max_history: usize = 256,

    pub fn init(allocator: std.mem.Allocator, max_history: usize) Tracker {
        return .{ .allocator = allocator, .max_history = max_history };
    }

    pub fn deinit(self: *Tracker) void {
        self.current_line.deinit(self.allocator);
        for (self.history.items) |*record| record.deinit(self.allocator);
        self.history.deinit(self.allocator);
        if (self.last_command) |value| self.allocator.free(value);
    }

    pub fn feedInput(self: *Tracker, bytes: []const u8) !void {
        for (bytes) |byte| {
            switch (byte) {
                '\r', '\n' => try self.commitCurrent(),
                0x08 => {
                    if (self.current_line.items.len != 0) _ = self.current_line.pop();
                },
                0x00...0x07, 0x09...0x09, 0x0b...0x0c, 0x0e...0x1f => {},
                else => try self.current_line.append(self.allocator, byte),
            }
        }
    }

    pub fn noteProcessExit(self: *Tracker, exit_code: ?u8) void {
        self.last_exit_code = exit_code;
    }

    pub fn lastCommandAlloc(self: *const Tracker, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.last_command orelse "");
    }

    pub fn historyAlloc(self: *const Tracker, allocator: std.mem.Allocator) ![]CommandRecord {
        var out = try allocator.alloc(CommandRecord, self.history.items.len);
        errdefer allocator.free(out);
        for (self.history.items, 0..) |record, i| {
            out[i] = .{
                .timestamp_ms = record.timestamp_ms,
                .text = try allocator.dupe(u8, record.text),
            };
        }
        return out;
    }

    fn commitCurrent(self: *Tracker) !void {
        const trimmed = std.mem.trim(u8, self.current_line.items, " \t");
        if (trimmed.len != 0) {
            if (self.last_command) |value| self.allocator.free(value);
            self.last_command = try self.allocator.dupe(u8, trimmed);
            if (self.history.items.len >= self.max_history) {
                var old = self.history.orderedRemove(0);
                old.deinit(self.allocator);
            }
            try self.history.append(self.allocator, .{
                .timestamp_ms = std.time.milliTimestamp(),
                .text = try self.allocator.dupe(u8, trimmed),
            });
        }
        self.current_line.clearRetainingCapacity();
    }
};

test "command tracker records committed commands" {
    var tracker = Tracker.init(std.testing.allocator, 8);
    defer tracker.deinit();
    try tracker.feedInput("dir\r");
    const last = try tracker.lastCommandAlloc(std.testing.allocator);
    defer std.testing.allocator.free(last);
    try std.testing.expectEqualStrings("dir", last);
}
