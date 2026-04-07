const std = @import("std");
const engine_mod = @import("engine.zig");
const state_mod = @import("state.zig");
const snapshot_mod = @import("snapshot.zig");

test "headless: multi-action sgr does not leak following csi bytes as text" {
    var engine = try engine_mod.Engine.init(std.testing.allocator, 6, 20);
    defer engine.deinit();

    engine.feed("\x1b[1;4m");
    engine.feed("\x1b[5;10H");
    engine.feed("X");

    try std.testing.expectEqual(@as(u21, 'X'), engine.state.grid.get(4, 9).char);
    try std.testing.expectEqual(@as(u21, ' '), engine.state.grid.get(0, 0).char);
}

test "headless: erase display clears stale content after redraw" {
    var engine = try engine_mod.Engine.init(std.testing.allocator, 4, 12);
    defer engine.deinit();

    engine.feed("hello");
    engine.feed("\x1b[2J\x1b[H");
    engine.feed("x");

    try std.testing.expectEqual(@as(u21, 'x'), engine.state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), engine.state.grid.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, ' '), engine.state.grid.get(0, 4).char);
}

test "headless: alt screen swaps buffers and restores main content" {
    var state = try state_mod.State.init(std.testing.allocator, 3, 8);
    defer state.deinit();

    state.apply(.{ .print = 'm' });
    state.apply(.{ .set_alt_screen = true });
    state.apply(.{ .print = 'a' });
    try std.testing.expectEqual(@as(u21, 'a'), state.alt_grid.getConst(0, 0).char);

    state.apply(.{ .set_alt_screen = false });
    try std.testing.expectEqual(@as(u21, 'm'), state.grid.getConst(0, 0).char);
}

test "headless: insert and delete chars behave like a terminal row edit" {
    var state = try state_mod.State.init(std.testing.allocator, 2, 8);
    defer state.deinit();

    state.apply(.{ .print = 'a' });
    state.apply(.{ .print = 'b' });
    state.apply(.{ .print = 'c' });
    state.setCursor(0, 1);
    state.apply(.{ .insert_chars = 1 });
    state.apply(.{ .print = 'X' });
    try std.testing.expectEqual(@as(u21, 'a'), state.grid.getConst(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'X'), state.grid.getConst(0, 1).char);
    try std.testing.expectEqual(@as(u21, 'b'), state.grid.getConst(0, 2).char);

    state.setCursor(0, 1);
    state.apply(.{ .delete_chars = 1 });
    try std.testing.expectEqual(@as(u21, 'b'), state.grid.getConst(0, 1).char);
}

test "headless: line edits scroll and snapshot correctly" {
    var state = try state_mod.State.init(std.testing.allocator, 2, 4);
    defer state.deinit();

    state.apply(.{ .print = 'a' });
    state.apply(.line_feed);
    state.apply(.line_feed);
    state.apply(.{ .print = 'b' });

    const out = try snapshot_mod.renderAlloc(std.testing.allocator, &state);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "b") != null);
}

test "headless: osc metadata is stored" {
    var engine = try engine_mod.Engine.init(std.testing.allocator, 2, 10);
    defer engine.deinit();

    engine.feed("\x1b]0;Demo\x07");
    engine.feed("\x1b]7;file://C:/work\x07");

    try std.testing.expectEqualStrings("Demo", engine.state.title.?);
    try std.testing.expect(std.mem.indexOf(u8, engine.state.cwd.?, "C:/work") != null);
}

test "headless: autowrap marks wrapped rows and continues on next row" {
    var engine = try engine_mod.Engine.init(std.testing.allocator, 3, 4);
    defer engine.deinit();

    engine.feed("ABCDE");

    try std.testing.expectEqual(@as(u21, 'A'), engine.state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'D'), engine.state.grid.get(0, 3).char);
    try std.testing.expect(engine.state.ring.getScreenWrapped(0));
    try std.testing.expectEqual(@as(u21, 'E'), engine.state.grid.get(1, 0).char);
}

test "headless: scroll region scrolls only inside margins" {
    var engine = try engine_mod.Engine.init(std.testing.allocator, 4, 3);
    defer engine.deinit();

    engine.feed("111\r\n222\r\n333\r\n444");
    engine.feed("\x1b[2;3r");
    engine.feed("\x1b[3;1H");
    engine.feed("\n");

    try std.testing.expectEqual(@as(u21, '1'), engine.state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '3'), engine.state.grid.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), engine.state.grid.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, '4'), engine.state.grid.get(3, 0).char);
}
