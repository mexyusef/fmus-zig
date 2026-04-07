const std = @import("std");
const cell_mod = @import("cell.zig");

pub const Cell = cell_mod.Cell;

pub const RingBuffer = struct {
    cells: []Cell,
    wrapped: []bool,
    cols: usize,
    capacity: usize,
    screen_rows: usize,
    head: usize,
    count: usize,
    allocator: std.mem.Allocator,

    pub const default_max_scrollback: usize = 5_000;

    pub fn init(
        allocator: std.mem.Allocator,
        screen_rows: usize,
        cols: usize,
        max_scrollback: usize,
    ) !RingBuffer {
        std.debug.assert(screen_rows > 0 and cols > 0);
        const capacity = screen_rows + max_scrollback;
        const cells = try allocator.alloc(Cell, capacity * cols);
        errdefer allocator.free(cells);
        @memset(cells, Cell{});
        const wrapped = try allocator.alloc(bool, capacity);
        errdefer allocator.free(wrapped);
        @memset(wrapped, false);
        return .{
            .cells = cells,
            .wrapped = wrapped,
            .cols = cols,
            .capacity = capacity,
            .screen_rows = screen_rows,
            .head = 0,
            .count = screen_rows,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RingBuffer) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.wrapped);
    }

    pub fn resizeScrollback(self: *RingBuffer, new_max_scrollback: usize) !void {
        const new_cap = self.screen_rows + new_max_scrollback;
        if (new_cap == self.capacity) return;

        const new_cells = try self.allocator.alloc(Cell, new_cap * self.cols);
        @memset(new_cells, Cell{});
        errdefer self.allocator.free(new_cells);
        const new_wrapped = try self.allocator.alloc(bool, new_cap);
        errdefer self.allocator.free(new_wrapped);
        @memset(new_wrapped, false);

        const rows_to_keep = @min(self.count, new_cap);
        const skip = self.count - rows_to_keep;
        for (0..rows_to_keep) |i| {
            const src_slot = self.ringSlot(skip + i);
            const src_off = src_slot * self.cols;
            const dst_off = i * self.cols;
            @memcpy(new_cells[dst_off..][0..self.cols], self.cells[src_off..][0..self.cols]);
            new_wrapped[i] = self.wrapped[src_slot];
        }

        self.allocator.free(self.cells);
        self.allocator.free(self.wrapped);
        self.cells = new_cells;
        self.wrapped = new_wrapped;
        self.capacity = new_cap;
        self.count = rows_to_keep;
        self.head = 0;
    }

    pub fn scrollbackCount(self: *const RingBuffer) usize {
        return if (self.count > self.screen_rows) self.count - self.screen_rows else 0;
    }

    fn ringSlot(self: *const RingBuffer, abs: usize) usize {
        return (self.head + abs) % self.capacity;
    }

    pub fn getRow(self: *const RingBuffer, abs: usize) []const Cell {
        std.debug.assert(abs < self.count);
        const slot = self.ringSlot(abs);
        const off = slot * self.cols;
        return self.cells[off .. off + self.cols];
    }

    pub fn getRowMut(self: *RingBuffer, abs: usize) []Cell {
        std.debug.assert(abs < self.count);
        const slot = self.ringSlot(abs);
        const off = slot * self.cols;
        return self.cells[off .. off + self.cols];
    }

    pub fn getWrapped(self: *const RingBuffer, abs: usize) bool {
        std.debug.assert(abs < self.count);
        return self.wrapped[self.ringSlot(abs)];
    }

    pub fn setWrapped(self: *RingBuffer, abs: usize, val: bool) void {
        std.debug.assert(abs < self.count);
        self.wrapped[self.ringSlot(abs)] = val;
    }

    pub fn screenAbsRow(self: *const RingBuffer, row: usize) usize {
        return self.scrollbackCount() + row;
    }

    pub fn getScreenCell(self: *const RingBuffer, row: usize, col: usize) Cell {
        const abs = self.screenAbsRow(row);
        const slot = self.ringSlot(abs);
        return self.cells[slot * self.cols + col];
    }

    pub fn setScreenCell(self: *RingBuffer, row: usize, col: usize, cell: Cell) void {
        const abs = self.screenAbsRow(row);
        const slot = self.ringSlot(abs);
        self.cells[slot * self.cols + col] = cell;
    }

    pub fn getScreenRow(self: *const RingBuffer, row: usize) []const Cell {
        return self.getRow(self.screenAbsRow(row));
    }

    pub fn getScreenRowMut(self: *RingBuffer, row: usize) []Cell {
        return self.getRowMut(self.screenAbsRow(row));
    }

    pub fn getScreenWrapped(self: *const RingBuffer, row: usize) bool {
        return self.getWrapped(self.screenAbsRow(row));
    }

    pub fn setScreenWrapped(self: *RingBuffer, row: usize, val: bool) void {
        self.setWrapped(self.screenAbsRow(row), val);
    }

    pub fn clearScreenRow(self: *RingBuffer, row: usize) void {
        @memset(self.getScreenRowMut(row), Cell{});
        self.setScreenWrapped(row, false);
    }

    pub fn viewportRow(self: *const RingBuffer, viewport_offset: usize, row: usize) []const Cell {
        const sb = self.scrollbackCount();
        const vp = @min(viewport_offset, sb);
        const abs = sb - vp + row;
        return self.getRow(abs);
    }

    pub fn viewportRowWrapped(self: *const RingBuffer, viewport_offset: usize, row: usize) bool {
        const sb = self.scrollbackCount();
        const vp = @min(viewport_offset, sb);
        const abs = sb - vp + row;
        return self.getWrapped(abs);
    }

    pub fn advanceScreen(self: *RingBuffer) bool {
        if (self.count < self.capacity) {
            self.count += 1;
        } else {
            self.head = (self.head + 1) % self.capacity;
        }
        self.clearScreenRow(self.screen_rows - 1);
        return true;
    }

    pub fn scrollUpRegion(self: *RingBuffer, top: usize, bottom: usize, blank: Cell) void {
        if (top >= bottom) return;
        var row = top;
        while (row < bottom) : (row += 1) {
            const dst = self.getScreenRowMut(row);
            const src = self.getScreenRow(row + 1);
            @memcpy(dst, src);
            self.setScreenWrapped(row, self.getScreenWrapped(row + 1));
        }
        @memset(self.getScreenRowMut(bottom), blank);
        self.setScreenWrapped(bottom, false);
    }

    pub fn scrollDownRegion(self: *RingBuffer, top: usize, bottom: usize, blank: Cell) void {
        if (top >= bottom) return;
        var row = bottom;
        while (row > top) : (row -= 1) {
            const dst = self.getScreenRowMut(row);
            const src = self.getScreenRow(row - 1);
            @memcpy(dst, src);
            self.setScreenWrapped(row, self.getScreenWrapped(row - 1));
        }
        @memset(self.getScreenRowMut(top), blank);
        self.setScreenWrapped(top, false);
    }

    pub fn scrollUpRegionN(self: *RingBuffer, top: usize, bottom: usize, n: usize, blank: Cell) void {
        if (top >= bottom or n == 0) return;
        const count = @min(n, bottom - top + 1);
        for (0..count) |_| self.scrollUpRegion(top, bottom, blank);
    }

    pub fn scrollUpTopAnchoredRegionWithScrollback(self: *RingBuffer, bottom: usize, blank: Cell) void {
        if (bottom >= self.screen_rows) return;

        _ = self.advanceScreen();
        if (bottom + 1 < self.screen_rows) {
            var row = self.screen_rows - 1;
            while (row > bottom) : (row -= 1) {
                const dst = self.getScreenRowMut(row);
                const src = self.getScreenRow(row - 1);
                @memcpy(dst, src);
                self.setScreenWrapped(row, self.getScreenWrapped(row - 1));
            }
        }

        @memset(self.getScreenRowMut(bottom), blank);
        self.setScreenWrapped(bottom, false);
    }

    pub fn scrollDownRegionN(self: *RingBuffer, top: usize, bottom: usize, n: usize, blank: Cell) void {
        if (top >= bottom or n == 0) return;
        const count = @min(n, bottom - top + 1);
        for (0..count) |_| self.scrollDownRegion(top, bottom, blank);
    }

    pub fn insertChars(self: *RingBuffer, row: usize, col: usize, n: usize, blank: Cell) void {
        if (n == 0 or col >= self.cols) return;
        const cells = self.getScreenRowMut(row);
        const count = @min(n, self.cols - col);
        const slice = cells[col..];
        if (count < slice.len) {
            std.mem.copyBackwards(Cell, slice[count..], slice[0 .. slice.len - count]);
        }
        @memset(slice[0..count], blank);
    }

    pub fn deleteChars(self: *RingBuffer, row: usize, col: usize, n: usize, blank: Cell) void {
        if (n == 0 or col >= self.cols) return;
        const cells = self.getScreenRowMut(row);
        const count = @min(n, self.cols - col);
        const slice = cells[col..];
        if (count < slice.len) {
            std.mem.copyForwards(Cell, slice[0 .. slice.len - count], slice[count..]);
        }
        @memset(slice[slice.len - count ..], blank);
    }

    pub fn eraseChars(self: *RingBuffer, row: usize, col: usize, n: usize, blank: Cell) void {
        if (n == 0 or col >= self.cols) return;
        const cells = self.getScreenRowMut(row);
        const count = @min(n, self.cols - col);
        @memset(cells[col .. col + count], blank);
    }

    pub fn clearScrollback(self: *RingBuffer) void {
        if (self.count <= self.screen_rows) return;
        const sb = self.scrollbackCount();
        self.head = (self.head + sb) % self.capacity;
        self.count = self.screen_rows;
    }

    pub fn screenCellsDirect(self: *const RingBuffer) ?[]const Cell {
        if (self.count == 0) return null;
        const first_abs = self.screenAbsRow(0);
        const first_slot = self.ringSlot(first_abs);
        const last_slot = self.ringSlot(first_abs + self.screen_rows - 1);
        if (last_slot >= first_slot) {
            const start = first_slot * self.cols;
            return self.cells[start .. start + self.screen_rows * self.cols];
        }
        return null;
    }

    pub fn screenCellsDirectMut(self: *RingBuffer) ?[]Cell {
        if (self.count == 0) return null;
        const first_abs = self.screenAbsRow(0);
        const first_slot = self.ringSlot(first_abs);
        const last_slot = self.ringSlot(first_abs + self.screen_rows - 1);
        if (last_slot >= first_slot) {
            const start = first_slot * self.cols;
            return self.cells[start .. start + self.screen_rows * self.cols];
        }
        return null;
    }
};

test "ring buffer stores viewport rows" {
    var ring = try RingBuffer.init(std.testing.allocator, 3, 4, 8);
    defer ring.deinit();

    ring.setScreenCell(0, 0, .{ .char = 'a' });
    _ = ring.advanceScreen();
    ring.setScreenCell(2, 0, .{ .char = 'b' });

    try std.testing.expectEqual(@as(u21, 'a'), ring.viewportRow(1, 0)[0].char);
    try std.testing.expectEqual(@as(u21, 'b'), ring.getScreenCell(2, 0).char);
}
