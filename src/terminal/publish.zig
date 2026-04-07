const std = @import("std");
const action_mod = @import("action.zig");
const cell_mod = @import("cell.zig");
const color_mod = @import("color.zig");
const dirty_mod = @import("dirty.zig");
const state_mod = @import("state.zig");

pub const RenderCell = struct {
    char: u21 = ' ',
    combining: [2]u21 = .{ 0, 0 },
    wide_continuation: bool = false,
    style: cell_mod.Cell = .{},
};

pub const RenderCursor = struct {
    row: usize = 0,
    col: usize = 0,
    visible: bool = true,
    shape: action_mod.CursorShape = .block,
};

pub const Frame = struct {
    allocator: std.mem.Allocator,
    rows: usize,
    cols: usize,
    cells: []cell_mod.Cell,
    wrapped: []bool,
    cursor: RenderCursor = .{},
    theme_colors: state_mod.ThemeColors = .{},

    pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Frame {
        const cells = try allocator.alloc(cell_mod.Cell, rows * cols);
        errdefer allocator.free(cells);
        @memset(cells, cell_mod.Cell{});
        const wrapped = try allocator.alloc(bool, rows);
        errdefer allocator.free(wrapped);
        @memset(wrapped, false);
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cells = cells,
            .wrapped = wrapped,
        };
    }

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.wrapped);
    }

    pub fn resize(self: *Frame, rows: usize, cols: usize) !void {
        if (self.rows == rows and self.cols == cols) return;
        self.allocator.free(self.cells);
        self.allocator.free(self.wrapped);
        self.cells = try self.allocator.alloc(cell_mod.Cell, rows * cols);
        @memset(self.cells, cell_mod.Cell{});
        self.wrapped = try self.allocator.alloc(bool, rows);
        @memset(self.wrapped, false);
        self.rows = rows;
        self.cols = cols;
    }

    pub fn cell(self: *const Frame, row: usize, col: usize) cell_mod.Cell {
        return self.cells[row * self.cols + col];
    }

    pub fn rowWrapped(self: *const Frame, row: usize) bool {
        return self.wrapped[row];
    }
};

pub fn publishAll(frame: *Frame, state: *const state_mod.State) !void {
    try frame.resize(state.rowCount(), state.colCount());
    fillRows(frame, state, null);
}

pub fn publishDirty(frame: *Frame, state: *const state_mod.State, dirty: *const dirty_mod.DirtyRows) !void {
    try frame.resize(state.rowCount(), state.colCount());
    fillRows(frame, state, dirty);
}

pub fn publishCursor(frame: *Frame, state: *const state_mod.State) void {
    frame.cursor = .{
        .row = state.cursor.row,
        .col = state.cursor.col,
        .visible = state.cursor.visible and state.viewport_offset == 0,
        .shape = state.cursor_shape,
    };
    frame.theme_colors = state.theme_colors;
}

fn fillRows(frame: *Frame, state: *const state_mod.State, dirty: ?*const dirty_mod.DirtyRows) void {
    const rows = state.rowCount();
    const cols = state.colCount();

    if (dirty == null) {
        if (state.screenCellsDirect()) |direct| {
            @memcpy(frame.cells, direct);
            var row_direct: usize = 0;
            while (row_direct < rows) : (row_direct += 1) {
                frame.wrapped[row_direct] = state.rowWrappedAtView(row_direct);
            }
            publishCursor(frame, state);
            return;
        }
    }

    var row: usize = 0;
    while (row < rows) : (row += 1) {
        if (dirty) |d| {
            if (!d.isDirty(row)) continue;
        }
        frame.wrapped[row] = state.rowWrappedAtView(row);
        var col: usize = 0;
        while (col < cols) : (col += 1) {
            frame.cells[row * cols + col] = state.cellAtView(row, col);
        }
    }
    publishCursor(frame, state);
}

test "publish all copies visible cells and cursor" {
    var state = try state_mod.State.init(std.testing.allocator, 3, 5);
    defer state.deinit();
    state.apply(.{ .print = 'A' });
    state.apply(.{ .cursor_position = .{ .row = 1, .col = 2 } });

    var frame = try Frame.init(std.testing.allocator, 1, 1);
    defer frame.deinit();
    try publishAll(&frame, &state);

    try std.testing.expectEqual(@as(u21, 'A'), frame.cell(0, 0).char);
    try std.testing.expectEqual(@as(usize, 1), frame.cursor.row);
    try std.testing.expectEqual(@as(usize, 2), frame.cursor.col);
}

test "publish dirty only updates marked rows" {
    var state = try state_mod.State.init(std.testing.allocator, 2, 4);
    defer state.deinit();
    var frame = try Frame.init(std.testing.allocator, 2, 4);
    defer frame.deinit();

    try publishAll(&frame, &state);
    state.apply(.{ .print = 'x' });
    try publishDirty(&frame, &state, &state.dirty);

    try std.testing.expectEqual(@as(u21, 'x'), frame.cell(0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), frame.cell(1, 0).char);
}
