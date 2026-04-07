const std = @import("std");
const grid_mod = @import("grid.zig");
const ring_mod = @import("ring.zig");

const Cell = ring_mod.Cell;
const RingBuffer = ring_mod.RingBuffer;
const isDefaultCell = grid_mod.isDefaultCell;

pub const ResizeResult = struct {
    ring: RingBuffer,
    cursor_row: usize,
    cursor_col: usize,
};

const LogicalLine = struct {
    start_abs: usize,
    row_count: usize,
    content_len: usize,
};

const max_logical_lines = 16384;

pub fn resize(
    old: *RingBuffer,
    new_screen_rows: usize,
    new_cols: usize,
    cursor_row: usize,
    cursor_col: usize,
) !ResizeResult {
    std.debug.assert(new_screen_rows > 0 and new_cols > 0);

    const old_cols = old.cols;
    const old_count = old.count;
    const max_scrollback = old.capacity - old.screen_rows;

    if (new_cols < old_cols) {
        stripRprompts(old, new_cols);
    }

    var ll_buf: [max_logical_lines]LogicalLine = undefined;
    var ll_count: usize = 0;
    var abs: usize = 0;
    while (abs < old_count) {
        if (ll_count >= max_logical_lines) break;
        const start = abs;
        var content_len: usize = 0;
        while (abs < old_count) : (abs += 1) {
            if (old.getWrapped(abs)) {
                content_len += old_cols;
            } else {
                const row = old.getRow(abs);
                var last: usize = 0;
                for (0..old_cols) |c| {
                    if (!isDefaultCell(row[c])) last = c + 1;
                }
                content_len += last;
                abs += 1;
                break;
            }
        }
        ll_buf[ll_count] = .{
            .start_abs = start,
            .row_count = abs - start,
            .content_len = content_len,
        };
        ll_count += 1;
    }

    const old_sb = old.scrollbackCount();
    const cursor_abs = old_sb + cursor_row;
    while (ll_count > 0) {
        const last = ll_buf[ll_count - 1];
        if (last.content_len > 0) break;
        if (cursor_abs >= last.start_abs and cursor_abs < last.start_abs + last.row_count) break;
        if (last.start_abs + last.row_count <= cursor_abs) break;
        ll_count -= 1;
    }
    if (ll_count == 0) ll_count = 1;

    var new_total: usize = 0;
    var new_sb_rows: usize = 0;
    var mapped_cr: usize = 0;
    var mapped_cc: usize = 0;
    for (ll_buf[0..ll_count]) |ll| {
        const rows_needed = if (ll.content_len == 0) 1 else (ll.content_len + new_cols - 1) / new_cols;
        if (cursor_abs >= ll.start_abs and cursor_abs < ll.start_abs + ll.row_count) {
            const offset_in_ll = (cursor_abs - ll.start_abs) * old_cols + cursor_col;
            mapped_cr = new_total + offset_in_ll / new_cols;
            mapped_cc = offset_in_ll % new_cols;
        }
        if (old_sb > 0 and ll.start_abs + ll.row_count <= old_sb) {
            new_sb_rows += rows_needed;
        } else if (old_sb > 0 and ll.start_abs < old_sb) {
            new_sb_rows += rows_needed;
        }
        new_total += rows_needed;
    }

    var new_ring = try RingBuffer.init(old.allocator, new_screen_rows, new_cols, max_scrollback);
    errdefer new_ring.deinit();

    var scroll_off: usize = 0;
    if (mapped_cr >= new_screen_rows) {
        scroll_off = mapped_cr - new_screen_rows + 1;
    }
    if (old_sb > 0) {
        scroll_off = @max(scroll_off, new_sb_rows);
    }

    const skip_rows = if (new_total > new_ring.capacity) new_total - new_ring.capacity else 0;
    new_ring.count = 0;
    new_ring.head = 0;

    var dst_row: usize = 0;
    for (ll_buf[0..ll_count]) |ll| {
        const rows_needed = if (ll.content_len == 0) 1 else (ll.content_len + new_cols - 1) / new_cols;
        for (0..rows_needed) |pr| {
            const abs_row = dst_row + pr;
            if (abs_row < skip_rows) continue;

            if (new_ring.count < new_ring.capacity) {
                new_ring.count += 1;
            } else {
                new_ring.head = (new_ring.head + 1) % new_ring.capacity;
            }

            const target_idx = new_ring.count - 1;
            const target_cells = new_ring.getRowMut(target_idx);
            @memset(target_cells, Cell{});

            const cells_start = pr * new_cols;
            const cells_end = @min(cells_start + new_cols, ll.content_len);
            if (cells_end > cells_start) {
                for (0..cells_end - cells_start) |c| {
                    const src_idx = cells_start + c;
                    const old_row_in_ll = src_idx / old_cols;
                    const old_col_in_ll = src_idx % old_cols;
                    const old_abs = ll.start_abs + old_row_in_ll;
                    if (old_abs < old_count) {
                        const src_row = old.getRow(old_abs);
                        if (old_col_in_ll < old_cols) target_cells[c] = src_row[old_col_in_ll];
                    }
                }
            }

            new_ring.setWrapped(target_idx, pr < rows_needed - 1);
        }
        dst_row += rows_needed;
    }

    const min_ring_count = @min(scroll_off + new_screen_rows, new_ring.capacity);
    while (new_ring.count < min_ring_count) {
        new_ring.count += 1;
        const idx = new_ring.count - 1;
        @memset(new_ring.getRowMut(idx), Cell{});
        new_ring.setWrapped(idx, false);
    }

    const adjusted_cr = if (mapped_cr >= skip_rows) mapped_cr - skip_rows else 0;
    const new_sb = new_ring.scrollbackCount();
    var final_cr = if (adjusted_cr >= new_sb) adjusted_cr - new_sb else 0;
    final_cr = @min(final_cr, new_screen_rows - 1);
    const final_cc = @min(mapped_cc, new_cols - 1);

    return .{
        .ring = new_ring,
        .cursor_row = final_cr,
        .cursor_col = final_cc,
    };
}

fn stripRprompts(ring: *RingBuffer, new_cols: usize) void {
    const cols = ring.cols;
    const gap_threshold: usize = @max(4, cols / 8);

    var abs: usize = 0;
    while (abs < ring.count) {
        const ll_start = abs;
        while (abs < ring.count and ring.getWrapped(abs)) : (abs += 1) {}
        abs += 1;
        const ll_end = @min(abs, ring.count);
        const ll_rows = ll_end - ll_start;

        var content_len: usize = 0;
        for (ll_start..ll_end) |r| {
            if (r < ll_end - 1) {
                content_len += cols;
            } else {
                const row = ring.getRow(r);
                var last: usize = 0;
                for (0..cols) |c| {
                    if (!isDefaultCell(row[c])) last = c + 1;
                }
                content_len += last;
            }
        }
        if (content_len <= new_cols) continue;

        var gap_start_pos: usize = 0;
        var gap_len: usize = 0;
        var found_gap = false;
        for (0..content_len) |pos| {
            const r = ll_start + pos / cols;
            const c = pos % cols;
            if (r >= ll_end) break;
            const row = ring.getRow(r);
            if (isDefaultCell(row[c])) {
                if (gap_len == 0) gap_start_pos = pos;
                gap_len += 1;
            } else {
                if (gap_len >= gap_threshold and gap_start_pos > 0) {
                    found_gap = true;
                    break;
                }
                gap_len = 0;
            }
        }
        if (!found_gap) continue;

        for (gap_start_pos..ll_rows * cols) |pos| {
            const r = ll_start + pos / cols;
            const c = pos % cols;
            if (r >= ll_end) break;
            ring.getRowMut(r)[c] = Cell{};
        }

        for (ll_start..ll_end) |r| {
            if (r == ll_end - 1) continue;
            const row = ring.getRow(r);
            if (isDefaultCell(row[cols - 1])) {
                ring.setWrapped(r, false);
            }
        }
    }
}

pub fn resizeNoReflow(
    old: *RingBuffer,
    new_screen_rows: usize,
    new_cols: usize,
) !RingBuffer {
    std.debug.assert(new_screen_rows > 0 and new_cols > 0);
    const max_scrollback = old.capacity - old.screen_rows;
    var new_ring = try RingBuffer.init(old.allocator, new_screen_rows, new_cols, max_scrollback);
    errdefer new_ring.deinit();

    const copy_rows = @min(old.screen_rows, new_screen_rows);
    const copy_cols = @min(old.cols, new_cols);

    for (0..copy_rows) |r| {
        const src = old.getScreenRow(r);
        const dst = new_ring.getScreenRowMut(r);
        @memcpy(dst[0..copy_cols], src[0..copy_cols]);
    }

    return new_ring;
}

test "ring_reflow: grow cols unwraps" {
    var ring = try RingBuffer.init(std.testing.allocator, 4, 3, 10);
    defer ring.deinit();

    ring.setScreenCell(0, 0, .{ .char = 'A' });
    ring.setScreenCell(0, 1, .{ .char = 'B' });
    ring.setScreenCell(0, 2, .{ .char = 'C' });
    ring.setScreenWrapped(0, true);
    ring.setScreenCell(1, 0, .{ .char = 'D' });
    ring.setScreenCell(1, 1, .{ .char = 'E' });
    ring.setScreenCell(1, 2, .{ .char = 'F' });

    const result = try resize(&ring, 4, 6, 1, 2);
    var new_ring = result.ring;
    defer new_ring.deinit();

    try std.testing.expectEqual(@as(u21, 'A'), new_ring.getScreenCell(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'F'), new_ring.getScreenCell(0, 5).char);
    try std.testing.expect(!new_ring.getScreenWrapped(0));
}

test "ring_reflow: shrink cols wraps" {
    var ring = try RingBuffer.init(std.testing.allocator, 2, 6, 10);
    defer ring.deinit();

    for ("ABCDEF", 0..) |ch, i| ring.setScreenCell(0, i, .{ .char = ch });

    const result = try resize(&ring, 4, 3, 0, 0);
    var new_ring = result.ring;
    defer new_ring.deinit();

    try std.testing.expectEqual(@as(u21, 'A'), new_ring.getScreenCell(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'C'), new_ring.getScreenCell(0, 2).char);
    try std.testing.expect(new_ring.getScreenWrapped(0));
    try std.testing.expectEqual(@as(u21, 'D'), new_ring.getScreenCell(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'F'), new_ring.getScreenCell(1, 2).char);
    try std.testing.expect(!new_ring.getScreenWrapped(1));
}

test "ring_reflow: scrollback content preserved" {
    var ring = try RingBuffer.init(std.testing.allocator, 2, 4, 10);
    defer ring.deinit();

    ring.setScreenCell(0, 0, .{ .char = 'A' });
    ring.setScreenCell(0, 1, .{ .char = 'B' });
    ring.setScreenCell(0, 2, .{ .char = 'C' });
    ring.setScreenCell(0, 3, .{ .char = 'D' });
    ring.setScreenCell(1, 0, .{ .char = 'E' });
    _ = ring.advanceScreen();
    ring.setScreenCell(1, 0, .{ .char = 'F' });

    try std.testing.expectEqual(@as(usize, 1), ring.scrollbackCount());

    const result = try resize(&ring, 2, 4, 1, 0);
    var new_ring = result.ring;
    defer new_ring.deinit();

    try std.testing.expectEqual(@as(usize, 1), new_ring.scrollbackCount());
    try std.testing.expectEqual(@as(u21, 'A'), new_ring.getRow(0)[0].char);
}
