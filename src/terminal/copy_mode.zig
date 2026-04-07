const std = @import("std");

pub const Mode = enum {
    off,
    navigate,
    visual,
    visual_line,
};

pub const Point = struct {
    row: usize,
    col: usize,
};

pub const State = struct {
    mode: Mode = .off,
    cursor: Point = .{ .row = 0, .col = 0 },
    anchor: Point = .{ .row = 0, .col = 0 },

    pub fn enter(self: *State, row: usize, col: usize) void {
        self.mode = .navigate;
        self.cursor = .{ .row = row, .col = col };
        self.anchor = self.cursor;
    }

    pub fn exit(self: *State) void {
        self.mode = .off;
    }

    pub fn isActive(self: *const State) bool {
        return self.mode != .off;
    }

    pub fn isVisual(self: *const State) bool {
        return self.mode == .visual or self.mode == .visual_line;
    }

    pub fn toggleVisual(self: *State) void {
        self.mode = switch (self.mode) {
            .navigate => blk: {
                self.anchor = self.cursor;
                break :blk .visual;
            },
            .visual => .navigate,
            else => self.mode,
        };
    }

    pub fn toggleVisualLine(self: *State) void {
        self.mode = switch (self.mode) {
            .navigate => blk: {
                self.anchor = self.cursor;
                break :blk .visual_line;
            },
            .visual_line => .navigate,
            else => self.mode,
        };
    }

    pub fn moveBy(self: *State, dr: isize, dc: isize, rows: usize, cols: usize) void {
        const nr = @as(isize, @intCast(self.cursor.row)) + dr;
        const nc = @as(isize, @intCast(self.cursor.col)) + dc;
        self.cursor.row = @intCast(@max(0, @min(@as(isize, @intCast(rows)) - 1, nr)));
        self.cursor.col = @intCast(@max(0, @min(@as(isize, @intCast(cols)) - 1, nc)));
    }

    pub fn selection(self: *const State, cols: usize) ?struct { start: Point, end: Point } {
        if (!self.isVisual()) return null;
        if (self.mode == .visual_line) {
            return .{
                .start = .{ .row = @min(self.anchor.row, self.cursor.row), .col = 0 },
                .end = .{ .row = @max(self.anchor.row, self.cursor.row), .col = cols - 1 },
            };
        }
        return .{
            .start = .{
                .row = @min(self.anchor.row, self.cursor.row),
                .col = @min(self.anchor.col, self.cursor.col),
            },
            .end = .{
                .row = @max(self.anchor.row, self.cursor.row),
                .col = @max(self.anchor.col, self.cursor.col),
            },
        };
    }
};

test "copy mode basic flow" {
    var s: State = .{};
    s.enter(4, 5);
    try std.testing.expect(s.isActive());
    s.toggleVisual();
    try std.testing.expect(s.isVisual());
    s.moveBy(2, 3, 20, 40);
    const sel = s.selection(40).?;
    try std.testing.expectEqual(@as(usize, 4), sel.start.row);
    try std.testing.expectEqual(@as(usize, 5), sel.start.col);
    try std.testing.expectEqual(@as(usize, 6), sel.end.row);
    try std.testing.expectEqual(@as(usize, 8), sel.end.col);
}
