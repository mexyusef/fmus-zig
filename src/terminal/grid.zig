const std = @import("std");
const cell_mod = @import("cell.zig");

pub fn isDefaultCell(cell: cell_mod.Cell) bool {
    return cell.char == ' ' and
        cell.combining[0] == 0 and
        cell.combining[1] == 0 and
        !cell.wide_continuation and
        cell.style.eql(.{});
}

pub const Grid = struct {
    allocator: std.mem.Allocator,
    rows: usize,
    cols: usize,
    cells: []cell_mod.Cell,

    pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Grid {
        const cells = try allocator.alloc(cell_mod.Cell, rows * cols);
        var grid = Grid{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cells = cells,
        };
        grid.clear();
        return grid;
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.cells);
    }

    pub fn clear(self: *Grid) void {
        for (self.cells) |*cell| cell.* = .{};
    }

    pub fn row(self: *Grid, row_index: usize) []cell_mod.Cell {
        const start = row_index * self.cols;
        return self.cells[start .. start + self.cols];
    }

    pub fn rowConst(self: *const Grid, row_index: usize) []const cell_mod.Cell {
        const start = row_index * self.cols;
        return self.cells[start .. start + self.cols];
    }

    pub fn get(self: *Grid, row_index: usize, col_index: usize) *cell_mod.Cell {
        return &self.cells[row_index * self.cols + col_index];
    }

    pub fn getConst(self: *const Grid, row_index: usize, col_index: usize) *const cell_mod.Cell {
        return &self.cells[row_index * self.cols + col_index];
    }

    pub fn clearRowFrom(self: *Grid, row_index: usize, start_col: usize) void {
        var col = start_col;
        while (col < self.cols) : (col += 1) {
            self.get(row_index, col).* = .{};
        }
    }

    pub fn clearRowTo(self: *Grid, row_index: usize, end_col: usize) void {
        var col: usize = 0;
        const stop = @min(end_col + 1, self.cols);
        while (col < stop) : (col += 1) {
            self.get(row_index, col).* = .{};
        }
    }

    pub fn clearRow(self: *Grid, row_index: usize) void {
        self.clearRowFrom(row_index, 0);
    }

    pub fn scrollUp(self: *Grid, count: usize) void {
        if (count == 0 or count >= self.rows) {
            self.clear();
            return;
        }

        var row_index: usize = 0;
        while (row_index + count < self.rows) : (row_index += 1) {
            const dst = self.row(row_index);
            const src = self.row(row_index + count);
            @memcpy(dst, src);
        }

        while (row_index < self.rows) : (row_index += 1) {
            self.clearRow(row_index);
        }
    }

    pub fn scrollUpRegion(self: *Grid, top: usize, bottom: usize, count: usize) void {
        if (top >= self.rows or bottom >= self.rows or top > bottom) return;
        const span = bottom - top + 1;
        if (count == 0 or count >= span) {
            var row_index = top;
            while (row_index <= bottom) : (row_index += 1) self.clearRow(row_index);
            return;
        }
        var row_index = top;
        while (row_index + count <= bottom) : (row_index += 1) {
            const dst = self.row(row_index);
            const src = self.row(row_index + count);
            @memcpy(dst, src);
        }
        while (row_index <= bottom) : (row_index += 1) self.clearRow(row_index);
    }

    pub fn scrollDownRegion(self: *Grid, top: usize, bottom: usize, count: usize) void {
        if (top >= self.rows or bottom >= self.rows or top > bottom) return;
        const span = bottom - top + 1;
        if (count == 0 or count >= span) {
            var row_index = top;
            while (row_index <= bottom) : (row_index += 1) self.clearRow(row_index);
            return;
        }
        var row_index: usize = bottom + 1 - count;
        while (true) {
            const dst = self.row(row_index + count - 1);
            const src = self.row(row_index - 1);
            @memcpy(dst, src);
            if (row_index == top + 1) break;
            row_index -= 1;
        }
        row_index = top;
        while (row_index < top + count) : (row_index += 1) self.clearRow(row_index);
    }

    pub fn insertChars(self: *Grid, row_index: usize, col_index: usize, count: usize) void {
        if (row_index >= self.rows or col_index >= self.cols) return;
        const row_cells = self.row(row_index);
        const n = @min(count, self.cols - col_index);
        if (n == 0) return;
        var col: usize = self.cols;
        while (col > col_index + n) {
            col -= 1;
            row_cells[col] = row_cells[col - n];
        }
        col = col_index;
        while (col < col_index + n) : (col += 1) row_cells[col] = .{};
    }

    pub fn deleteChars(self: *Grid, row_index: usize, col_index: usize, count: usize) void {
        if (row_index >= self.rows or col_index >= self.cols) return;
        const row_cells = self.row(row_index);
        const n = @min(count, self.cols - col_index);
        if (n == 0) return;
        var col = col_index;
        while (col + n < self.cols) : (col += 1) row_cells[col] = row_cells[col + n];
        while (col < self.cols) : (col += 1) row_cells[col] = .{};
    }

    pub fn resize(self: *Grid, rows: usize, cols: usize) !void {
        const new_cells = try self.allocator.alloc(cell_mod.Cell, rows * cols);
        for (new_cells) |*cell| cell.* = .{};

        const copy_rows = @min(self.rows, rows);
        const copy_cols = @min(self.cols, cols);

        var row_index: usize = 0;
        while (row_index < copy_rows) : (row_index += 1) {
            const old_row = self.rowConst(row_index);
            const start = row_index * cols;
            @memcpy(new_cells[start .. start + copy_cols], old_row[0..copy_cols]);
        }

        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.rows = rows;
        self.cols = cols;
    }

    pub fn resizeNoReflow(self: *Grid, rows: usize, cols: usize) !void {
        try self.resize(rows, cols);
    }
};
