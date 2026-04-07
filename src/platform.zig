pub const win32 = @import("platform/win32.zig");
pub const window = @import("platform/window.zig");
pub const png = @import("platform/png.zig");

pub const Window = window.Window;
pub const WindowConfig = window.Config;
pub const TextStyle = window.TextStyle;
pub const Canvas = window.Canvas;
pub const KeyModifiers = window.KeyModifiers;
pub const WindowMetrics = window.WindowMetrics;
pub const CMD_TOGGLE_FULLSCREEN = window.CMD_TOGGLE_FULLSCREEN;
pub const CMD_TOGGLE_ZEN = window.CMD_TOGGLE_ZEN;
pub const CMD_SCREENSHOT = window.CMD_SCREENSHOT;
pub const CMD_COMMAND_PALETTE = window.CMD_COMMAND_PALETTE;
pub const CMD_THEME_PICKER = window.CMD_THEME_PICKER;

test {
    _ = @import("platform/win32.zig");
    _ = @import("platform/window.zig");
    _ = @import("platform/png.zig");
}
