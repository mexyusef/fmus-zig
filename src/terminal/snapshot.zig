const std = @import("std");
const state_mod = @import("state.zig");
const view_mod = @import("view.zig");

pub fn renderAlloc(allocator: std.mem.Allocator, state: *const state_mod.State) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const screen = view_mod.ScreenView.init(state);

    var row_index: usize = 0;
    while (row_index < screen.rows()) : (row_index += 1) {
        var end = screen.cols();
        while (end > 0) : (end -= 1) {
            const tail = screen.cell(row_index, end - 1);
            if (tail.wide_continuation) continue;
            if (tail.char != ' ') break;
        }

        var col_index: usize = 0;
        while (col_index < end) : (col_index += 1) {
            const cell = screen.cell(row_index, col_index);
            if (cell.wide_continuation) continue;
            try appendCodepointUtf8(&out, allocator, cell.char);
        }
        if (row_index + 1 < screen.rows()) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn renderAllAlloc(allocator: std.mem.Allocator, state: *const state_mod.State) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const rows = state.totalRows();
    const cols = state.colCount();

    var row_index: usize = 0;
    while (row_index < rows) : (row_index += 1) {
        var end = cols;
        while (end > 0) : (end -= 1) {
            const tail = state.cellAtAbsolute(row_index, end - 1);
            if (tail.wide_continuation) continue;
            if (tail.char != ' ') break;
        }

        var col_index: usize = 0;
        while (col_index < end) : (col_index += 1) {
            const cell = state.cellAtAbsolute(row_index, col_index);
            if (cell.wide_continuation) continue;
            try appendCodepointUtf8(&out, allocator, cell.char);
        }
        if (row_index + 1 < rows) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

fn appendCodepointUtf8(out: *std.ArrayList(u8), allocator: std.mem.Allocator, codepoint: u21) !void {
    const cp: u21 = if (codepoint == 0) ' ' else switch (std.unicode.utf8ValidCodepoint(codepoint)) {
        true => codepoint,
        false => '?',
    };
    var buf: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(cp, &buf);
    try out.appendSlice(allocator, buf[0..len]);
}

test "snapshot trims trailing spaces" {
    var state = try state_mod.State.init(std.testing.allocator, 2, 6);
    defer state.deinit();
    state.apply(.{ .print = 'o' });
    state.apply(.{ .print = 'k' });

    const out = try renderAlloc(std.testing.allocator, &state);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("ok\n", out);
}

test "snapshot respects viewport scrollback" {
    var state = try state_mod.State.init(std.testing.allocator, 2, 4);
    defer state.deinit();
    state.apply(.{ .print = 'a' });
    state.apply(.line_feed);
    state.apply(.line_feed);
    state.apply(.{ .print = 'b' });
    state.scrollViewportUp(1);
    try std.testing.expectEqual(@as(usize, 1), state.scrollbackCount());

    const out = try renderAlloc(std.testing.allocator, &state);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "a") != null);
}

test "snapshot encodes unicode as utf8" {
    var state = try state_mod.State.init(std.testing.allocator, 1, 4);
    defer state.deinit();
    state.apply(.{ .print = 0x1F642 });

    const out = try renderAlloc(std.testing.allocator, &state);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("🙂", out);
}
