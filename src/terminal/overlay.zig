const std = @import("std");
const platform = @import("../platform.zig");
const paint_mod = @import("paint.zig");

pub const Mode = enum {
    command_palette,
    theme_picker,
};

pub const Action = enum {
    screenshot,
    toggle_fullscreen,
    toggle_zen,
    open_theme_picker,
    enter_copy_mode,
    theme_default,
    theme_mac_bw,
    theme_amber,
    copy,
    paste,
};

pub const Item = struct {
    label: []const u8,
    action: Action,
};

pub const State = struct {
    active: bool = false,
    mode: Mode = .command_palette,
    selected: usize = 0,

    pub fn open(self: *State, mode: Mode) void {
        self.active = true;
        self.mode = mode;
        self.selected = 0;
    }

    pub fn close(self: *State) void {
        self.active = false;
    }

    pub fn moveNext(self: *State) void {
        const items = activeItems(self.mode);
        if (items.len == 0) return;
        self.selected = (self.selected + 1) % items.len;
    }

    pub fn movePrev(self: *State) void {
        const items = activeItems(self.mode);
        if (items.len == 0) return;
        self.selected = if (self.selected == 0) items.len - 1 else self.selected - 1;
    }

    pub fn currentAction(self: *const State) ?Action {
        const items = activeItems(self.mode);
        if (!self.active or self.selected >= items.len) return null;
        return items[self.selected].action;
    }
};

pub fn activeItems(mode: Mode) []const Item {
    return switch (mode) {
        .command_palette => &command_palette_items,
        .theme_picker => &theme_items,
    };
}

pub fn paint(canvas: *platform.Canvas, metrics: paint_mod.Metrics, theme: paint_mod.Theme, state: State, rows: usize, cols: usize) void {
    if (!state.active) return;
    const panel_x = metrics.padding_px + metrics.cell_width_px * 3;
    const panel_y = metrics.padding_px + metrics.cell_height_px * 3;
    const panel_w = @max(metrics.cell_width_px * 34, @as(i32, @intCast(cols)) * metrics.cell_width_px - metrics.cell_width_px * 8);
    const panel_h = @min(@as(i32, @intCast(rows)) * metrics.cell_height_px - metrics.cell_height_px * 6, metrics.cell_height_px * 14);
    const backdrop = mixRgb(theme.background_rgb, 0x00000000, 0.70);
    const panel_bg = mixRgb(theme.background_rgb, 0x00202020, 0.82);
    const border = mixRgb(theme.foreground_rgb, 0x00000000, 0.55);
    const header_fg = theme.foreground_rgb;
    const selected_bg = theme.cursor_rgb;
    const selected_fg = theme.cursor_text_rgb;

    canvas.fillRect(0, 0, 10000, 10000, backdrop);
    canvas.fillRect(panel_x, panel_y, panel_w, panel_h, panel_bg);
    canvas.fillRect(panel_x, panel_y, panel_w, 2, border);
    canvas.fillRect(panel_x, panel_y + panel_h - 2, panel_w, 2, border);
    canvas.fillRect(panel_x, panel_y, 2, panel_h, border);
    canvas.fillRect(panel_x + panel_w - 2, panel_y, 2, panel_h, border);

    var utf16_buf: [128]u16 = undefined;
    const title = switch (state.mode) {
        .command_palette => "Command Palette",
        .theme_picker => "Theme Picker",
    };
    drawUtf8(canvas, panel_x + metrics.cell_width_px, panel_y + @divFloor(metrics.cell_height_px, 2), panel_w - metrics.cell_width_px * 2, title, header_fg, &utf16_buf);

    const items = activeItems(state.mode);
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        const y = panel_y + metrics.cell_height_px * @as(i32, @intCast(i + 2));
        if (i == state.selected) {
            canvas.fillRect(panel_x + metrics.cell_width_px, y - 2, panel_w - metrics.cell_width_px * 2, metrics.cell_height_px + 4, selected_bg);
        }
        drawUtf8(
            canvas,
            panel_x + metrics.cell_width_px * 2,
            y,
            panel_w - metrics.cell_width_px * 4,
            items[i].label,
            if (i == state.selected) selected_fg else header_fg,
            &utf16_buf,
        );
    }
}

fn drawUtf8(canvas: *platform.Canvas, x: i32, y: i32, width: i32, text: []const u8, rgb: u32, buf: []u16) void {
    const len = std.unicode.utf8ToUtf16Le(buf, text) catch 0;
    canvas.drawText(x, y, width, buf[0..len], rgb, false, .{});
}

fn mixRgb(a: u32, b: u32, t: f32) u32 {
    const ar: f32 = @floatFromInt(a & 0xff);
    const ag: f32 = @floatFromInt((a >> 8) & 0xff);
    const ab: f32 = @floatFromInt((a >> 16) & 0xff);
    const br: f32 = @floatFromInt(b & 0xff);
    const bg: f32 = @floatFromInt((b >> 8) & 0xff);
    const bb: f32 = @floatFromInt((b >> 16) & 0xff);
    const rr: u32 = @intFromFloat(ar * (1.0 - t) + br * t);
    const rg: u32 = @intFromFloat(ag * (1.0 - t) + bg * t);
    const rb: u32 = @intFromFloat(ab * (1.0 - t) + bb * t);
    return rr | (rg << 8) | (rb << 16);
}

const command_palette_items = [_]Item{
    .{ .label = "Take Screenshot", .action = .screenshot },
    .{ .label = "Toggle Fullscreen", .action = .toggle_fullscreen },
    .{ .label = "Toggle Zen", .action = .toggle_zen },
    .{ .label = "Enter Copy Mode", .action = .enter_copy_mode },
    .{ .label = "Theme Picker", .action = .open_theme_picker },
    .{ .label = "Copy Selection", .action = .copy },
    .{ .label = "Paste Clipboard", .action = .paste },
};

const theme_items = [_]Item{
    .{ .label = "Default", .action = .theme_default },
    .{ .label = "Mac Black/White", .action = .theme_mac_bw },
    .{ .label = "Amber", .action = .theme_amber },
};

test "overlay state navigation works" {
    var state: State = .{};
    state.open(.command_palette);
    try std.testing.expect(state.active);
    state.moveNext();
    try std.testing.expectEqual(@as(usize, 1), state.selected);
    state.movePrev();
    try std.testing.expectEqual(@as(usize, 0), state.selected);
}
