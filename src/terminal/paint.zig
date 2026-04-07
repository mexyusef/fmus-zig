const std = @import("std");
const cell_mod = @import("cell.zig");
const color_mod = @import("color.zig");
const unicode = @import("unicode.zig");
const platform = @import("../platform.zig");
const publish_mod = @import("publish.zig");
const view_mod = @import("view.zig");

pub const Metrics = struct {
    cell_width_px: i32 = 11,
    cell_height_px: i32 = 22,
    padding_px: i32 = 24,
    cursor_width_px: i32 = 11,
    cursor_height_px: i32 = 3,
    cursor_bar_width_px: i32 = 2,
    underline_height_px: i32 = 2,
    strikethrough_height_px: i32 = 2,
};

pub const CursorShape = enum {
    block,
    underline,
    bar,
};

pub const Theme = struct {
    background_rgb: u32 = 0x00161A1D,
    foreground_rgb: u32 = 0x00D8E6F0,
    cursor_rgb: u32 = 0x00E8C547,
    cursor_text_rgb: u32 = 0x00161A1D,
    cursor_shape: CursorShape = .block,
    selection_bg_rgb: u32 = 0x005A748A,
    selection_fg_rgb: ?u32 = null,
};

pub const Selection = struct {
    start_row: usize,
    start_col: usize,
    end_row: usize,
    end_col: usize,
};

pub const ThemePreset = enum {
    default,
    mac_bw,
    amber,
};

pub fn themePreset(preset: ThemePreset) Theme {
    return switch (preset) {
        .default => .{},
        .mac_bw => .{
            .background_rgb = 0x00000000,
            .foreground_rgb = 0x00F2F2F2,
            .cursor_rgb = 0x00F2F2F2,
            .cursor_text_rgb = 0x00000000,
            .cursor_shape = .block,
        },
        .amber => .{
            .background_rgb = 0x000B0906,
            .foreground_rgb = 0x0047D7FF,
            .cursor_rgb = 0x0047D7FF,
            .cursor_text_rgb = 0x000B0906,
            .cursor_shape = .block,
        },
    };
}

pub fn windowStylePreset(preset: ThemePreset) platform.TextStyle {
    return switch (preset) {
        .default => .{},
        .mac_bw => .{
            .background_rgb = 0x00000000,
            .foreground_rgb = 0x00F2F2F2,
            .font_name = "Cascadia Mono",
            .font_height = 22,
            .padding = 24,
        },
        .amber => .{
            .background_rgb = 0x000B0906,
            .foreground_rgb = 0x0047D7FF,
            .font_name = "Cascadia Mono",
            .font_height = 22,
            .padding = 24,
        },
    };
}

pub fn paintScreen(canvas: *platform.Canvas, screen: view_mod.ScreenView, metrics: Metrics, theme: Theme) void {
    const default_bg = theme.background_rgb;
    const default_fg = theme.foreground_rgb;
    const rows = screen.rows();
    const cols = screen.cols();

    var glyph_buf: [8]u16 = [_]u16{0} ** 8;

    var row: usize = 0;
    while (row < rows) : (row += 1) {
        var col: usize = 0;
        while (col < cols) : (col += 1) {
            const cell = screen.cell(row, col);
            const x = metrics.padding_px + @as(i32, @intCast(col)) * metrics.cell_width_px;
            const y = metrics.padding_px + @as(i32, @intCast(row)) * metrics.cell_height_px;
            var bg = colorToRgb(cell.style.bg, default_bg);
            var fg = colorToRgb(cell.style.fg, default_fg);
            if (cell.style.reverse) {
                const tmp = fg;
                fg = bg;
                bg = tmp;
            }
            if (cell.style.dim) fg = dimRgb(fg);
            canvas.fillRect(x, y, metrics.cell_width_px, metrics.cell_height_px, bg);
            if (cell.wide_continuation) continue;

            const glyph_len = encodeCellUtf16(&glyph_buf, cell);
            const draw_width = if (cellDisplayWidth(cell) == 2) metrics.cell_width_px * 2 else metrics.cell_width_px;
            canvas.drawText(x, y, draw_width, glyph_buf[0..glyph_len], fg, cellNeedsEmojiFont(cell), .{
                .bold = cell.style.bold,
                .italic = cell.style.italic,
            });
            if (cell.style.underline) {
                canvas.fillRect(
                    x,
                    y + metrics.cell_height_px - metrics.underline_height_px,
                    draw_width,
                    metrics.underline_height_px,
                    fg,
                );
            }
            if (cell.style.strikethrough) {
                canvas.fillRect(
                    x,
                    y + @divFloor(metrics.cell_height_px, 2),
                    draw_width,
                    metrics.strikethrough_height_px,
                    fg,
                );
            }
        }
    }

    if (screen.cursorVisible()) {
        const cursor_col = screen.cursorCol();
        const cursor_row = screen.cursorRow();
        const cursor_x = metrics.padding_px + @as(i32, @intCast(cursor_col)) * metrics.cell_width_px;
        const cursor_y = metrics.padding_px + @as(i32, @intCast(cursor_row)) * metrics.cell_height_px;
        const cursor_cell = screen.cell(cursor_row, cursor_col);
        const cursor_shape = switch (screen.cursorShape()) {
            .block => CursorShape.block,
            .underline => CursorShape.underline,
            .bar => CursorShape.bar,
        };
        switch (cursor_shape) {
            .block => {
                const cursor_w = if (cellDisplayWidth(cursor_cell) == 2) metrics.cell_width_px * 2 else metrics.cell_width_px;
                canvas.fillRect(cursor_x, cursor_y, cursor_w, metrics.cell_height_px, theme.cursor_rgb);
                const glyph_len = encodeCellUtf16(&glyph_buf, cursor_cell);
                const draw_width = if (cellDisplayWidth(cursor_cell) == 2) metrics.cell_width_px * 2 else metrics.cell_width_px;
                canvas.drawText(cursor_x, cursor_y, draw_width, glyph_buf[0..glyph_len], theme.cursor_text_rgb, cellNeedsEmojiFont(cursor_cell), .{
                    .bold = cursor_cell.style.bold,
                    .italic = cursor_cell.style.italic,
                });
            },
            .underline => {
                canvas.fillRect(
                    cursor_x,
                    cursor_y + metrics.cell_height_px - metrics.cursor_height_px,
                    metrics.cursor_width_px,
                    metrics.cursor_height_px,
                    theme.cursor_rgb,
                );
            },
            .bar => {
                canvas.fillRect(cursor_x, cursor_y, metrics.cursor_bar_width_px, metrics.cell_height_px, theme.cursor_rgb);
            },
        }
    }
}

pub fn paintFrame(canvas: *platform.Canvas, frame: *const publish_mod.Frame, metrics: Metrics, theme: Theme) void {
    const default_bg = rgbToColorref(frame.theme_colors.bg, theme.background_rgb);
    const default_fg = rgbToColorref(frame.theme_colors.fg, theme.foreground_rgb);
    const cursor_rgb = if (frame.theme_colors.cursor) |rgb| rgbToColorref(rgb, theme.cursor_rgb) else theme.cursor_rgb;
    const rows = frame.rows;
    const cols = frame.cols;

    var glyph_buf: [8]u16 = [_]u16{0} ** 8;

    var row: usize = 0;
    while (row < rows) : (row += 1) {
        var col: usize = 0;
        while (col < cols) : (col += 1) {
            const cell = frame.cell(row, col);
            const x = metrics.padding_px + @as(i32, @intCast(col)) * metrics.cell_width_px;
            const y = metrics.padding_px + @as(i32, @intCast(row)) * metrics.cell_height_px;
            var bg = colorToRgb(cell.style.bg, default_bg);
            var fg = colorToRgb(cell.style.fg, default_fg);
            if (cell.style.reverse) {
                const tmp = fg;
                fg = bg;
                bg = tmp;
            }
            if (cell.style.dim) fg = dimRgb(fg);
            canvas.fillRect(x, y, metrics.cell_width_px, metrics.cell_height_px, bg);
            if (cell.wide_continuation) continue;

            const glyph_len = encodeCellUtf16(&glyph_buf, cell);
            const draw_width = if (cellDisplayWidth(cell) == 2) metrics.cell_width_px * 2 else metrics.cell_width_px;
            canvas.drawText(x, y, draw_width, glyph_buf[0..glyph_len], fg, cellNeedsEmojiFont(cell), .{
                .bold = cell.style.bold,
                .italic = cell.style.italic,
            });
            if (cell.style.underline) {
                canvas.fillRect(x, y + metrics.cell_height_px - metrics.underline_height_px, draw_width, metrics.underline_height_px, fg);
            }
            if (cell.style.strikethrough) {
                canvas.fillRect(x, y + @divFloor(metrics.cell_height_px, 2), draw_width, metrics.strikethrough_height_px, fg);
            }
        }
    }

    if (frame.cursor.visible and frame.cursor.row < rows and frame.cursor.col < cols) {
        const cursor_x = metrics.padding_px + @as(i32, @intCast(frame.cursor.col)) * metrics.cell_width_px;
        const cursor_y = metrics.padding_px + @as(i32, @intCast(frame.cursor.row)) * metrics.cell_height_px;
        const cursor_cell = frame.cell(frame.cursor.row, frame.cursor.col);
        const cursor_shape = switch (frame.cursor.shape) {
            .block => CursorShape.block,
            .underline => CursorShape.underline,
            .bar => CursorShape.bar,
        };
        switch (cursor_shape) {
            .block => {
                const cursor_w = if (cellDisplayWidth(cursor_cell) == 2) metrics.cell_width_px * 2 else metrics.cell_width_px;
                canvas.fillRect(cursor_x, cursor_y, cursor_w, metrics.cell_height_px, cursor_rgb);
                const glyph_len = encodeCellUtf16(&glyph_buf, cursor_cell);
                const draw_width = if (cellDisplayWidth(cursor_cell) == 2) metrics.cell_width_px * 2 else metrics.cell_width_px;
                canvas.drawText(cursor_x, cursor_y, draw_width, glyph_buf[0..glyph_len], theme.cursor_text_rgb, cellNeedsEmojiFont(cursor_cell), .{
                    .bold = cursor_cell.style.bold,
                    .italic = cursor_cell.style.italic,
                });
            },
            .underline => {
                const cursor_w = if (cellDisplayWidth(cursor_cell) == 2) metrics.cell_width_px * 2 else metrics.cursor_width_px;
                canvas.fillRect(cursor_x, cursor_y + metrics.cell_height_px - metrics.cursor_height_px, cursor_w, metrics.cursor_height_px, cursor_rgb);
            },
            .bar => canvas.fillRect(cursor_x, cursor_y, metrics.cursor_bar_width_px, metrics.cell_height_px, cursor_rgb),
        }
    }
}

pub fn paintSelectionFrame(canvas: *platform.Canvas, frame: *const publish_mod.Frame, metrics: Metrics, theme: Theme, selection: Selection) void {
    const row_start = @min(selection.start_row, selection.end_row);
    const row_end = @max(selection.start_row, selection.end_row);
    const col_start = @min(selection.start_col, selection.end_col);
    const col_end = @max(selection.start_col, selection.end_col);
    var glyph_buf: [8]u16 = [_]u16{0} ** 8;

    var row = row_start;
    while (row <= row_end and row < frame.rows) : (row += 1) {
        const start_col = if (row == row_start) col_start else 0;
        const end_col = if (row == row_end) col_end else frame.cols - 1;
        var col = start_col;
        while (col <= end_col and col < frame.cols) : (col += 1) {
            const cell = frame.cell(row, col);
            if (cell.wide_continuation) continue;
            const x = metrics.padding_px + @as(i32, @intCast(col)) * metrics.cell_width_px;
            const y = metrics.padding_px + @as(i32, @intCast(row)) * metrics.cell_height_px;
            const draw_width = if (cellDisplayWidth(cell) == 2) metrics.cell_width_px * 2 else metrics.cell_width_px;
            canvas.fillRect(x, y, draw_width, metrics.cell_height_px, theme.selection_bg_rgb);
            const fg = theme.selection_fg_rgb orelse colorToRgb(cell.style.fg, theme.foreground_rgb);
            const glyph_len = encodeCellUtf16(&glyph_buf, cell);
            canvas.drawText(x, y, draw_width, glyph_buf[0..glyph_len], fg, cellNeedsEmojiFont(cell), .{
                .bold = cell.style.bold,
                .italic = cell.style.italic,
            });
        }
    }
}

fn rgbToColorref(rgb: color_mod.Rgb, fallback: u32) u32 {
    _ = fallback;
    return (@as(u32, rgb.b) << 16) | (@as(u32, rgb.g) << 8) | @as(u32, rgb.r);
}

fn encodeCellUtf16(buf: *[8]u16, cell: cell_mod.Cell) usize {
    var len: usize = 0;
    len += encodeCodepointUtf16(buf[len..], cell.char);
    for (cell.combining) |cp| {
        if (cp == 0) break;
        len += encodeCodepointUtf16(buf[len..], cp);
    }
    return if (len == 0) 1 else len;
}

fn encodeCodepointUtf16(buf: []u16, codepoint: u21) usize {
    const cp: u32 = if (codepoint == 0) ' ' else codepoint;
    if (cp <= 0xD7FF or (cp >= 0xE000 and cp <= 0xFFFF)) {
        buf[0] = @intCast(cp);
        return 1;
    }
    if (cp <= 0x10FFFF) {
        const value = cp - 0x10000;
        buf[0] = @intCast(0xD800 + ((value >> 10) & 0x3FF));
        buf[1] = @intCast(0xDC00 + (value & 0x3FF));
        return 2;
    }

    buf[0] = '?';
    return 1;
}

fn cellDisplayWidth(cell: cell_mod.Cell) u2 {
    if (cell.wide_continuation) return 1;
    return unicode.charDisplayWidth(cell.char);
}

fn cellNeedsEmojiFont(cell: cell_mod.Cell) bool {
    if (unicode.charDisplayWidth(cell.char) == 2 and cell.char >= 0x1F000) return true;
    if (unicode.isTextDefaultEmoji(cell.char)) return true;
    for (cell.combining) |cp| {
        if (cp == 0) break;
        if (cp == 0xFE0F or (cp >= 0x1F3FB and cp <= 0x1F3FF)) return true;
    }
    return false;
}

fn colorToRgb(color: color_mod.Color, fallback: u32) u32 {
    return switch (color) {
        .default => fallback,
        .named => |named| switch (named) {
            .default => fallback,
            .black => 0x001E1E1E,
            .red => 0x003A5CCC,
            .green => 0x0039A248,
            .yellow => 0x0000A5D6,
            .blue => 0x00CC7A00,
            .magenta => 0x009D4EDD,
            .cyan => 0x00C8A200,
            .white => 0x00D8E6F0,
            .bright_black => 0x005E5E5E,
            .bright_red => 0x006B7CFF,
            .bright_green => 0x0050D26D,
            .bright_yellow => 0x002CC6FF,
            .bright_blue => 0x00FFAA3B,
            .bright_magenta => 0x00C77DFF,
            .bright_cyan => 0x00E1C542,
            .bright_white => 0x00F4F7FA,
        },
        .indexed => |index| indexedToRgb(index),
        .rgb => |rgb| (@as(u32, rgb.b) << 16) | (@as(u32, rgb.g) << 8) | @as(u32, rgb.r),
    };
}

fn indexedToRgb(index: u8) u32 {
    if (index < 16) {
        const named = switch (index) {
            0 => color_mod.Color{ .named = .black },
            1 => color_mod.Color{ .named = .red },
            2 => color_mod.Color{ .named = .green },
            3 => color_mod.Color{ .named = .yellow },
            4 => color_mod.Color{ .named = .blue },
            5 => color_mod.Color{ .named = .magenta },
            6 => color_mod.Color{ .named = .cyan },
            7 => color_mod.Color{ .named = .white },
            8 => color_mod.Color{ .named = .bright_black },
            9 => color_mod.Color{ .named = .bright_red },
            10 => color_mod.Color{ .named = .bright_green },
            11 => color_mod.Color{ .named = .bright_yellow },
            12 => color_mod.Color{ .named = .bright_blue },
            13 => color_mod.Color{ .named = .bright_magenta },
            14 => color_mod.Color{ .named = .bright_cyan },
            else => color_mod.Color{ .named = .bright_white },
        };
        return colorToRgb(named, 0);
    }

    if (index >= 232) {
        const shade: u8 = @intCast(8 + ((index - 232) * 10));
        return (@as(u32, shade) << 16) | (@as(u32, shade) << 8) | @as(u32, shade);
    }

    const value = index - 16;
    const r = value / 36;
    const g = (value % 36) / 6;
    const b = value % 6;
    const component = [_]u8{ 0, 95, 135, 175, 215, 255 };
    return (@as(u32, component[b]) << 16) | (@as(u32, component[g]) << 8) | @as(u32, component[r]);
}

fn dimRgb(rgb: u32) u32 {
    const r: u8 = @intCast(rgb & 0xff);
    const g: u8 = @intCast((rgb >> 8) & 0xff);
    const b: u8 = @intCast((rgb >> 16) & 0xff);
    return (@as(u32, b / 2) << 16) | (@as(u32, g / 2) << 8) | @as(u32, r / 2);
}

test "paint module compiles" {
    try std.testing.expect(@sizeOf(Metrics) > 0);
}
