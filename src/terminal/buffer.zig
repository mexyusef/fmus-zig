const std = @import("std");
const state_mod = @import("state.zig");

pub const Row = struct {
    text: []u8,
    wrapped: bool,

    pub fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

pub const Snapshot = struct {
    rows: []Row,
    cursor_row: usize,
    cursor_col: usize,
    cursor_visible: bool,
    total_rows: usize,
    viewport_offset: usize,

    pub fn deinit(self: *Snapshot, allocator: std.mem.Allocator) void {
        for (self.rows) |*row| row.deinit(allocator);
        allocator.free(self.rows);
    }
};

pub fn visibleAlloc(allocator: std.mem.Allocator, state: *const state_mod.State) !Snapshot {
    const row_count = state.rowCount();
    var rows = try allocator.alloc(Row, row_count);
    errdefer allocator.free(rows);
    for (0..row_count) |row| {
        rows[row] = .{
            .text = try rowTextAtViewAlloc(allocator, state, row),
            .wrapped = state.rowWrappedAtView(row),
        };
    }
    return .{
        .rows = rows,
        .cursor_row = state.cursor.row,
        .cursor_col = state.cursor.col,
        .cursor_visible = state.cursor.visible,
        .total_rows = state.totalRows(),
        .viewport_offset = state.viewport_offset,
    };
}

pub fn scrollbackAlloc(allocator: std.mem.Allocator, state: *const state_mod.State) !Snapshot {
    const row_count = state.scrollbackAbsoluteRows();
    var rows = try allocator.alloc(Row, row_count);
    errdefer allocator.free(rows);
    for (0..row_count) |row| {
        rows[row] = .{
            .text = try rowTextAtAbsoluteAlloc(allocator, state, row),
            .wrapped = if (row < state.rowCount()) state.rowWrappedAtView(row) else false,
        };
    }
    return .{
        .rows = rows,
        .cursor_row = state.cursor.row,
        .cursor_col = state.cursor.col,
        .cursor_visible = state.cursor.visible,
        .total_rows = state.totalRows(),
        .viewport_offset = state.viewport_offset,
    };
}

fn rowTextAtViewAlloc(allocator: std.mem.Allocator, state: *const state_mod.State, row: usize) ![]u8 {
    return rowTextAlloc(allocator, state, row, true);
}

fn rowTextAtAbsoluteAlloc(allocator: std.mem.Allocator, state: *const state_mod.State, row: usize) ![]u8 {
    return rowTextAlloc(allocator, state, row, false);
}

fn rowTextAlloc(allocator: std.mem.Allocator, state: *const state_mod.State, row: usize, comptime view: bool) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const cols = state.colCount();
    var last_non_space: usize = 0;
    for (0..cols) |col| {
        const cell = if (view) state.cellAtView(row, col) else state.cellAtAbsolute(row, col);
        if (cell.wide_continuation) continue;
        var buf: [8]u8 = undefined;
        const len = std.unicode.utf8Encode(cell.char, &buf) catch 0;
        if (len == 0) continue;
        try out.appendSlice(allocator, buf[0..len]);
        if (cell.char != ' ') last_non_space = out.items.len;
    }
    try out.resize(allocator, last_non_space);
    return out.toOwnedSlice(allocator);
}

test "buffer visible snapshot collects rows" {
    var state = try state_mod.State.init(std.testing.allocator, 3, 8);
    defer state.deinit();
    state.apply(.{ .print = 'a' });
    state.apply(.line_feed);
    state.apply(.{ .print = 'b' });
    var snap = try visibleAlloc(std.testing.allocator, &state);
    defer snap.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("a", snap.rows[0].text);
    try std.testing.expectEqualStrings(" b", snap.rows[1].text);
}
