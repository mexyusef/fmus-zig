const std = @import("std");
const action_mod = @import("action.zig");
const parser_mod = @import("parser.zig");
const state_mod = @import("state.zig");

pub const Engine = struct {
    parser: parser_mod.Parser = .{},
    state: state_mod.State,
    utf8_len: usize = 0,
    utf8_expected: usize = 0,
    utf8_buf: [4]u8 = .{ 0, 0, 0, 0 },

    pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Engine {
        return .{
            .state = try state_mod.State.init(allocator, rows, cols),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.state.deinit();
    }

    pub fn resize(self: *Engine, rows: usize, cols: usize) !void {
        try self.state.resize(rows, cols);
    }

    pub fn feed(self: *Engine, bytes: []const u8) void {
        for (bytes) |byte| {
            const action = self.nextAction(byte) orelse continue;
            self.state.apply(action);
            while (self.nextPendingAction()) |pending| {
                self.state.apply(pending);
            }
        }
    }

    pub fn nextAction(self: *Engine, byte: u8) ?action_mod.Action {
        if (self.tryUtf8Continuation(byte)) |action| return action;
        if (self.parser.isGround() and byte >= 0x80) {
            if (self.beginUtf8(byte)) return null;
        }
        return self.parser.next(byte);
    }

    pub fn nextPendingAction(self: *Engine) ?action_mod.Action {
        return self.parser.nextPending();
    }

    fn beginUtf8(self: *Engine, first: u8) bool {
        const expected = std.unicode.utf8ByteSequenceLength(first) catch return false;
        if (expected <= 1 or expected > self.utf8_buf.len) return false;
        self.utf8_buf[0] = first;
        self.utf8_len = 1;
        self.utf8_expected = expected;
        return true;
    }

    fn tryUtf8Continuation(self: *Engine, byte: u8) ?action_mod.Action {
        if (self.utf8_expected == 0) return null;
        self.utf8_buf[self.utf8_len] = byte;
        self.utf8_len += 1;
        if (self.utf8_len < self.utf8_expected) return action_mod.Action.nop;

        const slice = self.utf8_buf[0..self.utf8_expected];
        const codepoint = std.unicode.utf8Decode(slice) catch blk: {
            self.resetUtf8();
            break :blk null;
        };
        self.resetUtf8();
        if (codepoint) |cp| return .{ .print = cp };
        return .nop;
    }

    fn resetUtf8(self: *Engine) void {
        self.utf8_len = 0;
        self.utf8_expected = 0;
    }
};

test "engine feeds bytes into state" {
    var engine = try Engine.init(std.testing.allocator, 4, 8);
    defer engine.deinit();

    engine.feed("hi");
    try std.testing.expectEqual(@as(u21, 'h'), engine.state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), engine.state.grid.get(0, 1).char);
}

test "engine resize preserves state content" {
    var engine = try Engine.init(std.testing.allocator, 2, 4);
    defer engine.deinit();

    engine.feed("ab");
    try engine.resize(4, 6);

    try std.testing.expectEqual(@as(u21, 'a'), engine.state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'b'), engine.state.grid.get(0, 1).char);
}

test "engine decodes utf8 codepoints" {
    var engine = try Engine.init(std.testing.allocator, 2, 8);
    defer engine.deinit();

    engine.feed("A\xc3\xa9");
    try std.testing.expectEqual(@as(u21, 'A'), engine.state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 0xE9), engine.state.grid.get(0, 1).char);
}
