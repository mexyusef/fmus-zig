const std = @import("std");
const paint_mod = @import("paint.zig");
const platform = @import("../platform.zig");

pub const ButtonId = enum {
    automation_server,
    screenshot,
    palette,
    theme,
    fullscreen,
    zen,
};

pub const Button = struct {
    id: ButtonId,
    icon: []const u8,
    label: []const u8,
    tooltip: []const u8,
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn contains(self: Rect, px: i32, py: i32) bool {
        return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h;
    }
};

pub const LayoutItem = struct {
    button: Button,
    rect: Rect,
};

pub const Layout = struct {
    items: [6]LayoutItem,
    len: usize = 0,

    pub fn hitTest(self: Layout, x: i32, y: i32) ?ButtonId {
        for (self.items[0..self.len]) |item| {
            if (item.rect.contains(x, y)) return item.button.id;
        }
        return null;
    }

    pub fn tooltip(self: Layout, id: ButtonId) ?[]const u8 {
        for (self.items[0..self.len]) |item| {
            if (item.button.id == id) return item.button.tooltip;
        }
        return null;
    }
};

pub fn defaultButtons(include_automation: bool) [6]Button {
    return if (include_automation)
        .{
            .{ .id = .automation_server, .icon = "WS", .label = "Serve", .tooltip = "Start terminal automation server" },
            .{ .id = .screenshot, .icon = "[]", .label = "Shot", .tooltip = "Take screenshot (F10)" },
            .{ .id = .palette, .icon = ">>", .label = "Cmd", .tooltip = "Open command palette (Ctrl+P)" },
            .{ .id = .theme, .icon = "**", .label = "Theme", .tooltip = "Open theme picker (Ctrl+T)" },
            .{ .id = .fullscreen, .icon = "[]", .label = "Full", .tooltip = "Toggle fullscreen (F11)" },
            .{ .id = .zen, .icon = "--", .label = "Zen", .tooltip = "Toggle zen mode (F12)" },
        }
    else
        .{
            .{ .id = .screenshot, .icon = "[]", .label = "Shot", .tooltip = "Take screenshot (F10)" },
            .{ .id = .palette, .icon = ">>", .label = "Cmd", .tooltip = "Open command palette (Ctrl+P)" },
            .{ .id = .theme, .icon = "**", .label = "Theme", .tooltip = "Open theme picker (Ctrl+T)" },
            .{ .id = .fullscreen, .icon = "[]", .label = "Full", .tooltip = "Toggle fullscreen (F11)" },
            .{ .id = .zen, .icon = "--", .label = "Zen", .tooltip = "Toggle zen mode (F12)" },
            .{ .id = .zen, .icon = "", .label = "", .tooltip = "" },
        };
}

pub fn layout(width_px: i32, metrics: paint_mod.Metrics, toolbar_height_px: i32, include_automation: bool) Layout {
    const buttons = defaultButtons(include_automation);
    var result: Layout = .{ .items = undefined, .len = 0 };
    var x = metrics.padding_px;
    const y = metrics.padding_px;
    const button_h = @max(22, toolbar_height_px - 6);
    for (buttons) |button| {
        if (button.label.len == 0) continue;
        const w = buttonWidth(button);
        result.items[result.len] = .{
            .button = button,
            .rect = .{
                .x = x,
                .y = y,
                .w = w,
                .h = button_h,
            },
        };
        result.len += 1;
        x += w + 8;
        if (x >= width_px - metrics.padding_px) break;
    }
    return result;
}

pub fn paint(canvas: *platform.Canvas, width_px: i32, metrics: paint_mod.Metrics, theme: paint_mod.Theme, toolbar_height_px: i32, hovered: ?ButtonId, pressed: ?ButtonId, include_automation: bool) void {
    const bar_y = metrics.padding_px;
    const bar_h = @max(24, toolbar_height_px);
    canvas.fillRect(metrics.padding_px, bar_y, @max(1, width_px - metrics.padding_px * 2), bar_h, mixRgb(theme.background_rgb, theme.foreground_rgb, 0.08));
    const items = layout(width_px, metrics, toolbar_height_px, include_automation);
    for (items.items[0..items.len]) |item| {
        const is_hover = hovered != null and hovered.? == item.button.id;
        const is_pressed = pressed != null and pressed.? == item.button.id;
        const bg = if (is_pressed)
            mixRgb(theme.cursor_rgb, theme.background_rgb, 0.45)
        else if (is_hover)
            mixRgb(theme.foreground_rgb, theme.background_rgb, 0.18)
        else
            mixRgb(theme.background_rgb, theme.foreground_rgb, 0.12);
        const fg = if (is_pressed) theme.cursor_text_rgb else theme.foreground_rgb;
        canvas.fillRect(item.rect.x, item.rect.y, item.rect.w, item.rect.h, bg);
        drawUtf8(canvas, item.rect.x + 8, item.rect.y + 4, item.rect.w - 16, item.button.icon, fg);
        drawUtf8(canvas, item.rect.x + 32, item.rect.y + 4, item.rect.w - 36, item.button.label, fg);
    }
}

fn buttonWidth(button: Button) i32 {
    return @max(74, @as(i32, @intCast((button.icon.len + button.label.len) * 10 + 26)));
}

fn drawUtf8(canvas: *platform.Canvas, x: i32, y: i32, width: i32, text: []const u8, rgb: u32) void {
    var buf: [64]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, text) catch return;
    canvas.drawText(x, y, width, buf[0..len], rgb, false, .{ .bold = true });
}

fn mixRgb(a: u32, b: u32, t: f32) u32 {
    const ar: f32 = @floatFromInt(a & 0xff);
    const ag: f32 = @floatFromInt((a >> 8) & 0xff);
    const ab: f32 = @floatFromInt((a >> 16) & 0xff);
    const br: f32 = @floatFromInt(b & 0xff);
    const bg: f32 = @floatFromInt((b >> 8) & 0xff);
    const bb: f32 = @floatFromInt((b >> 16) & 0xff);
    const r: u32 = @intFromFloat(ar + (br - ar) * t);
    const g: u32 = @intFromFloat(ag + (bg - ag) * t);
    const b2: u32 = @intFromFloat(ab + (bb - ab) * t);
    return (b2 << 16) | (g << 8) | r;
}

test "toolbar layout hit test works" {
    const metrics = paint_mod.Metrics{};
    const l = layout(900, metrics, 30, true);
    try std.testing.expect(l.hitTest(metrics.padding_px + 4, metrics.padding_px + 4) != null);
}
