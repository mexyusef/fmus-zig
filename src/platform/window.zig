const builtin = @import("builtin");
const std = @import("std");
const win32 = @import("win32.zig");
const png = @import("png.zig");
const input_mod = @import("../terminal/input.zig");
const SRCCOPY: win32.DWORD = 0x00CC0020;

pub const TextStyle = struct {
    background_rgb: u32 = 0x00161A1D,
    foreground_rgb: u32 = 0x00D8E6F0,
    font_name: []const u8 = "Cascadia Mono",
    font_fallbacks: []const []const u8 = &.{
        "Segoe UI Emoji",
        "Segoe UI Symbol",
        "Microsoft YaHei UI",
    },
    font_height: i32 = 22,
    padding: i32 = 24,
};

pub const FontMetrics = struct {
    cell_width_px: i32 = 11,
    cell_height_px: i32 = 22,
    baseline_px: i32 = 17,
};

pub const TextAttrs = struct {
    bold: bool = false,
    italic: bool = false,
};

pub const KeyModifiers = struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    super_key: bool = false,
};

pub const Callbacks = struct {
    on_paint: ?*const fn (ctx: *anyopaque, canvas: *Canvas) anyerror!bool = null,
    on_tick: ?*const fn (ctx: *anyopaque) anyerror!void = null,
    on_char: ?*const fn (ctx: *anyopaque, codepoint: u21, mods: KeyModifiers) anyerror!void = null,
    on_key_down: ?*const fn (ctx: *anyopaque, vkey: u32, mods: KeyModifiers, is_repeat: bool) anyerror!void = null,
    on_key_up: ?*const fn (ctx: *anyopaque, vkey: u32, mods: KeyModifiers) anyerror!void = null,
    on_mouse_wheel: ?*const fn (ctx: *anyopaque, delta: i16) anyerror!void = null,
    on_mouse_event: ?*const fn (ctx: *anyopaque, ev: input_mod.MouseEvent) anyerror!void = null,
    on_resize: ?*const fn (ctx: *anyopaque, width: i32, height: i32) anyerror!void = null,
    on_focus_changed: ?*const fn (ctx: *anyopaque, focused: bool) anyerror!void = null,
    on_command: ?*const fn (ctx: *anyopaque, command_id: u16) anyerror!void = null,
    on_destroy: ?*const fn (ctx: *anyopaque) anyerror!void = null,
};

pub const WindowMetrics = struct {
    window_rect: win32.Rect = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    client_rect: win32.Rect = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    monitor_rect: win32.Rect = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    work_rect: win32.Rect = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    monitor_index: u32 = 0,
    screen_width_px: i32 = 0,
    screen_height_px: i32 = 0,
    free_disk_bytes: u64 = 0,
};

pub const Config = struct {
    title: []const u8,
    class_name: []const u8 = "FMUSWindow",
    width: i32 = 1120,
    height: i32 = 760,
    text: []const u8 = "",
    style: TextStyle = .{},
    icon_path: ?[]const u8 = null,
    show_menu: bool = true,
    show_footer: bool = true,
    footer_height_px: i32 = 28,
    timer_interval_ms: u32 = 0,
    callbacks: Callbacks = .{},
    callback_ctx: ?*anyopaque = null,
};

pub const Window = if (builtin.os.tag == .windows) WindowsWindow else StubWindow;

pub const Canvas = if (builtin.os.tag == .windows) WindowsCanvas else StubCanvas;
pub const CMD_TOGGLE_FULLSCREEN: u16 = 0x1001;
pub const CMD_TOGGLE_ZEN: u16 = 0x1002;
pub const CMD_SCREENSHOT: u16 = 0x1003;
pub const CMD_COMMAND_PALETTE: u16 = 0x1004;
pub const CMD_THEME_PICKER: u16 = 0x1005;

const StubWindow = struct {
    pub fn init(_: std.mem.Allocator, _: Config) !StubWindow {
        return error.UnsupportedPlatform;
    }

    pub fn deinit(_: *StubWindow) void {}

    pub fn run(_: *StubWindow) !void {
        return error.UnsupportedPlatform;
    }

    pub fn setCallbackContext(_: *StubWindow, _: ?*anyopaque) void {}

    pub fn setText(_: *StubWindow, _: []const u8) !void {
        return error.UnsupportedPlatform;
    }

    pub fn setTitle(_: *StubWindow, _: []const u8) !void {
        return error.UnsupportedPlatform;
    }

    pub fn requestRepaint(_: *StubWindow) void {}

    pub fn fontMetrics(_: *const StubWindow) FontMetrics {
        return .{};
    }

    pub fn footerHeight(_: *const StubWindow) i32 {
        return 0;
    }

    pub fn setFooterText(_: *StubWindow, _: []const u8) !void {}
    pub fn applyStyle(_: *StubWindow, _: TextStyle) !void {}

    pub fn metrics(_: *StubWindow) WindowMetrics {
        return .{};
    }

    pub fn toggleFullscreen(_: *StubWindow) !void {
        return error.UnsupportedPlatform;
    }

    pub fn toggleZen(_: *StubWindow) !void {
        return error.UnsupportedPlatform;
    }

    pub fn copyTextToClipboard(_: *StubWindow, _: []const u8) !void {
        return error.UnsupportedPlatform;
    }

    pub fn readTextFromClipboard(_: *StubWindow, _: std.mem.Allocator) ![]u8 {
        return error.UnsupportedPlatform;
    }

    pub fn saveClientScreenshotPng(_: *StubWindow, _: []const u8) !void {
        return error.UnsupportedPlatform;
    }
};

const StubCanvas = struct {
    pub fn fillRect(_: *StubCanvas, _: i32, _: i32, _: i32, _: i32, _: u32) void {}
    pub fn drawText(_: *StubCanvas, _: i32, _: i32, _: i32, _: []const u16, _: u32, _: bool, _: TextAttrs) void {}
};

const WindowsWindow = struct {
    allocator: std.mem.Allocator,
    api: win32.Api,
    instance: win32.HINSTANCE,
    class_name: [:0]u16,
    title: [:0]u16,
    text: []u16,
    footer_text: []u16,
    font_name: [:0]u16,
    style: TextStyle,
    width_px: i32,
    height_px: i32,
    font: win32.HFONT = null,
    font_bold: win32.HFONT = null,
    font_italic: win32.HFONT = null,
    font_bold_italic: win32.HFONT = null,
    emoji_font_name: [:0]u16,
    emoji_font: win32.HFONT = null,
    fallback_font_names: [4]?[:0]u16 = .{ null, null, null, null },
    fallback_fonts: [4]win32.HFONT = .{ null, null, null, null },
    bg_brush: win32.HBRUSH = null,
    timer_interval_ms: u32,
    footer_height_px: i32,
    show_footer: bool,
    show_menu: bool,
    callbacks: Callbacks,
    callback_ctx: ?*anyopaque,
    hwnd: ?win32.HWND = null,
    menu: win32.HMENU = null,
    menu_label_fullscreen: ?[:0]u16 = null,
    menu_label_zen: ?[:0]u16 = null,
    menu_label_screenshot: ?[:0]u16 = null,
    menu_label_palette: ?[:0]u16 = null,
    menu_label_theme: ?[:0]u16 = null,
    menu_label_exit: ?[:0]u16 = null,
    icon_path: ?[:0]u16 = null,
    fullscreen: bool = false,
    zen: bool = false,
    restore_style: isize = 0,
    restore_placement: win32.WINDOWPLACEMENT = .{
        .length = @sizeOf(win32.WINDOWPLACEMENT),
        .flags = 0,
        .showCmd = 0,
        .ptMinPosition = .{ .x = 0, .y = 0 },
        .ptMaxPosition = .{ .x = 0, .y = 0 },
        .rcNormalPosition = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    },
    suppress_char: bool = false,
    mouse_buttons: input_mod.MouseButton = .none,
    focused: bool = true,
    tracking_mouse_leave: bool = false,
    font_metrics: FontMetrics = .{},

    const CMD_EXIT: u16 = 0x10FF;
    const WM_FMUS_REPAINT: win32.UINT = win32.WM_APP + 1;

    var active: ?*WindowsWindow = null;

    pub fn init(allocator: std.mem.Allocator, config: Config) !WindowsWindow {
        var self = WindowsWindow{
            .allocator = allocator,
            .api = try win32.Api.load(),
            .instance = try win32.moduleHandle(),
            .class_name = try win32.utf8ToWideZ(allocator, config.class_name),
            .title = try win32.utf8ToWideZ(allocator, config.title),
            .text = try win32.utf8ToWide(allocator, config.text),
            .footer_text = try win32.utf8ToWide(allocator, ""),
            .font_name = try win32.utf8ToWideZ(allocator, config.style.font_name),
            .emoji_font_name = try win32.utf8ToWideZ(allocator, "Segoe UI Emoji"),
            .style = config.style,
            .width_px = config.width,
            .height_px = config.height,
            .timer_interval_ms = config.timer_interval_ms,
            .footer_height_px = @max(0, config.footer_height_px),
            .show_footer = config.show_footer,
            .show_menu = config.show_menu,
            .callbacks = config.callbacks,
            .callback_ctx = config.callback_ctx,
            .suppress_char = false,
            .font_metrics = .{},
        };
        errdefer self.deinit();

        self.bg_brush = self.api.gdi32.create_solid_brush(config.style.background_rgb);
        if (self.bg_brush == null) return error.CreateBrushFailed;

        self.font = self.createFontVariant(self.font_name.ptr, config.style.font_height, false, false, true);
        if (self.font == null) return error.CreateFontFailed;
        self.font_bold = self.createFontVariant(self.font_name.ptr, config.style.font_height, true, false, true);
        if (self.font_bold == null) return error.CreateFontFailed;
        self.font_italic = self.createFontVariant(self.font_name.ptr, config.style.font_height, false, true, true);
        if (self.font_italic == null) return error.CreateFontFailed;
        self.font_bold_italic = self.createFontVariant(self.font_name.ptr, config.style.font_height, true, true, true);
        if (self.font_bold_italic == null) return error.CreateFontFailed;

        self.emoji_font = self.createFontVariant(self.emoji_font_name.ptr, config.style.font_height, false, false, false);
        if (self.emoji_font == null) return error.CreateFontFailed;

        for (config.style.font_fallbacks[0..@min(config.style.font_fallbacks.len, self.fallback_font_names.len)], 0..) |fallback_name, index| {
            self.fallback_font_names[index] = try win32.utf8ToWideZ(allocator, fallback_name);
            self.fallback_fonts[index] = self.createFontVariant(self.fallback_font_names[index].?.ptr, config.style.font_height, false, false, false);
        }

        if (config.icon_path) |path| {
            self.icon_path = try win32.utf8ToWideZ(allocator, path);
        }
        self.menu_label_fullscreen = try win32.utf8ToWideZ(allocator, "[ ] Toggle &Fullscreen\tF11");
        self.menu_label_zen = try win32.utf8ToWideZ(allocator, "[-] Toggle &Zen\tF12");
        self.menu_label_screenshot = try win32.utf8ToWideZ(allocator, "[#] Take &Screenshot\tF10");
        self.menu_label_palette = try win32.utf8ToWideZ(allocator, "[>] &Command Palette\tCtrl+P");
        self.menu_label_theme = try win32.utf8ToWideZ(allocator, "[*] &Theme Picker\tCtrl+T");
        self.menu_label_exit = try win32.utf8ToWideZ(allocator, "E&xit");

        self.font_metrics = self.measureFontMetrics();

        return self;
    }

    pub fn deinit(self: *WindowsWindow) void {
        if (self.font) |font| _ = self.api.gdi32.delete_object(@ptrCast(font));
        if (self.font_bold) |font| _ = self.api.gdi32.delete_object(@ptrCast(font));
        if (self.font_italic) |font| _ = self.api.gdi32.delete_object(@ptrCast(font));
        if (self.font_bold_italic) |font| _ = self.api.gdi32.delete_object(@ptrCast(font));
        if (self.emoji_font) |font| _ = self.api.gdi32.delete_object(@ptrCast(font));
        for (self.fallback_fonts) |font| {
            if (font) |f| _ = self.api.gdi32.delete_object(@ptrCast(f));
        }
        if (self.bg_brush) |brush| _ = self.api.gdi32.delete_object(@ptrCast(brush));
        freeWideZ(self.allocator, self.class_name);
        freeWideZ(self.allocator, self.title);
        self.allocator.free(self.text);
        self.allocator.free(self.footer_text);
        freeWideZ(self.allocator, self.font_name);
        freeWideZ(self.allocator, self.emoji_font_name);
        if (self.icon_path) |path| freeWideZ(self.allocator, path);
        if (self.menu_label_fullscreen) |text| freeWideZ(self.allocator, text);
        if (self.menu_label_zen) |text| freeWideZ(self.allocator, text);
        if (self.menu_label_screenshot) |text| freeWideZ(self.allocator, text);
        if (self.menu_label_palette) |text| freeWideZ(self.allocator, text);
        if (self.menu_label_theme) |text| freeWideZ(self.allocator, text);
        if (self.menu_label_exit) |text| freeWideZ(self.allocator, text);
        for (self.fallback_font_names) |name| {
            if (name) |n| freeWideZ(self.allocator, n);
        }
    }

    pub fn run(self: *WindowsWindow) !void {
        const wc = win32.WndClassW{
            .style = win32.CS_HREDRAW | win32.CS_VREDRAW,
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = self.instance,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = self.bg_brush,
            .lpszMenuName = null,
            .lpszClassName = self.class_name.ptr,
        };

        if (self.api.user32.register_class_w(&wc) == 0) return error.RegisterClassFailed;

        active = self;
        defer active = null;

        self.hwnd = self.api.user32.create_window_ex_w(
            0,
            self.class_name.ptr,
            self.title.ptr,
            win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            self.windowWidth(),
            self.windowHeight(),
            null,
            null,
            self.instance,
            null,
        ) orelse return error.CreateWindowFailed;

        if (self.icon_path) |path| self.loadWindowIcon(path);
        try self.applyMenuState();

        if (self.timer_interval_ms != 0) {
            if (self.api.user32.set_timer(self.hwnd, 1, self.timer_interval_ms, null) == 0) {
                return error.SetTimerFailed;
            }
        }
        defer {
            if (self.timer_interval_ms != 0) {
                _ = self.api.user32.kill_timer(self.hwnd, 1);
            }
        }

        _ = self.api.user32.show_window(self.hwnd, win32.SW_SHOW);
        _ = self.api.user32.update_window(self.hwnd);

        var msg: win32.Msg = undefined;
        while (self.api.user32.get_message_w(&msg, null, 0, 0) > 0) {
            _ = self.api.user32.translate_message(&msg);
            _ = self.api.user32.dispatch_message_w(&msg);
        }
    }

    pub fn setCallbackContext(self: *WindowsWindow, ctx: ?*anyopaque) void {
        self.callback_ctx = ctx;
    }

    pub fn setText(self: *WindowsWindow, text: []const u8) !void {
        self.allocator.free(self.text);
        self.text = try win32.utf8ToWide(self.allocator, text);
    }

    pub fn setTitle(self: *WindowsWindow, title: []const u8) !void {
        freeWideZ(self.allocator, self.title);
        self.title = try win32.utf8ToWideZ(self.allocator, title);
        if (self.hwnd) |hwnd| {
            _ = self.api.user32.set_window_text_w(hwnd, self.title.ptr);
        }
    }

    pub fn requestRepaint(self: *WindowsWindow) void {
        if (self.hwnd) |hwnd| {
            _ = self.api.user32.post_message_w(hwnd, WM_FMUS_REPAINT, 0, 0);
        }
    }

    pub fn fontMetrics(self: *const WindowsWindow) FontMetrics {
        return self.font_metrics;
    }

    pub fn footerHeight(self: *const WindowsWindow) i32 {
        return if (self.show_footer and !self.zen) self.footer_height_px else 0;
    }

    pub fn setFooterText(self: *WindowsWindow, text: []const u8) !void {
        self.allocator.free(self.footer_text);
        self.footer_text = try win32.utf8ToWide(self.allocator, text);
        self.requestRepaint();
    }

    pub fn applyStyle(self: *WindowsWindow, style: TextStyle) !void {
        self.style = style;
        if (self.bg_brush) |brush| _ = self.api.gdi32.delete_object(@ptrCast(brush));
        self.bg_brush = self.api.gdi32.create_solid_brush(style.background_rgb);
        if (self.bg_brush == null) return error.CreateBrushFailed;
        self.requestRepaint();
    }

    pub fn metrics(self: *WindowsWindow) WindowMetrics {
        var result: WindowMetrics = .{};
        const hwnd = self.hwnd orelse return result;
        _ = self.api.user32.get_window_rect(hwnd, &result.window_rect);
        _ = self.api.user32.get_client_rect(hwnd, &result.client_rect);
        result.screen_width_px = self.api.user32.get_system_metrics(win32.SM_CXSCREEN);
        result.screen_height_px = self.api.user32.get_system_metrics(win32.SM_CYSCREEN);
        if (self.api.user32.monitor_from_window(hwnd, win32.MONITOR_DEFAULTTONEAREST)) |monitor| {
            var info = win32.MONITORINFO{
                .cbSize = @sizeOf(win32.MONITORINFO),
                .rcMonitor = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
                .rcWork = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
                .dwFlags = 0,
            };
            if (self.api.user32.get_monitor_info_w(monitor, &info) != 0) {
                result.monitor_rect = info.rcMonitor;
                result.work_rect = info.rcWork;
            }
            result.monitor_index = self.monitorIndex(monitor);
        }
        const drive_root: [4:0]u16 = .{ 'C', ':', '\\', 0 };
        _ = win32.GetDiskFreeSpaceExW(&drive_root, &result.free_disk_bytes, null, null);
        return result;
    }

    pub fn toggleFullscreen(self: *WindowsWindow) !void {
        const hwnd = self.hwnd orelse return;
        if (!self.fullscreen) {
            self.restore_style = self.api.user32.get_window_long_ptr_w(hwnd, win32.GWL_STYLE);
            self.restore_placement.length = @sizeOf(win32.WINDOWPLACEMENT);
            _ = self.api.user32.get_window_placement(hwnd, &self.restore_placement);
            const monitor = self.api.user32.monitor_from_window(hwnd, win32.MONITOR_DEFAULTTONEAREST) orelse return;
            var info = win32.MONITORINFO{
                .cbSize = @sizeOf(win32.MONITORINFO),
                .rcMonitor = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
                .rcWork = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
                .dwFlags = 0,
            };
            if (self.api.user32.get_monitor_info_w(monitor, &info) == 0) return error.GetMonitorInfoFailed;
            _ = self.api.user32.set_window_long_ptr_w(hwnd, win32.GWL_STYLE, @as(isize, @intCast(win32.WS_VISIBLE | win32.WS_POPUP)));
            _ = self.api.user32.set_window_pos(
                hwnd,
                null,
                info.rcMonitor.left,
                info.rcMonitor.top,
                info.rcMonitor.right - info.rcMonitor.left,
                info.rcMonitor.bottom - info.rcMonitor.top,
                win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED,
            );
            self.fullscreen = true;
        } else {
            _ = self.api.user32.set_window_long_ptr_w(hwnd, win32.GWL_STYLE, self.baseWindowStyle());
            _ = self.api.user32.set_window_placement(hwnd, &self.restore_placement);
            _ = self.api.user32.set_window_pos(hwnd, null, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED);
            _ = self.api.user32.show_window(hwnd, win32.SW_RESTORE);
            self.fullscreen = false;
        }
        try self.applyMenuState();
        self.requestRepaint();
    }

    pub fn toggleZen(self: *WindowsWindow) !void {
        self.zen = !self.zen;
        if (!self.fullscreen) {
            const hwnd = self.hwnd orelse return;
            _ = self.api.user32.set_window_long_ptr_w(hwnd, win32.GWL_STYLE, self.baseWindowStyle());
            _ = self.api.user32.set_window_pos(hwnd, null, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED);
        }
        try self.applyMenuState();
        self.requestRepaint();
    }

    pub fn copyTextToClipboard(self: *WindowsWindow, text: []const u8) !void {
        const wide = try win32.utf8ToWideZ(self.allocator, text);
        defer freeWideZ(self.allocator, wide);
        const bytes = (wide.len + 1) * @sizeOf(u16);
        const mem = self.api.global_alloc(win32.GMEM_MOVEABLE, bytes) orelse return error.GlobalAllocFailed;
        errdefer _ = self.api.global_free(mem);
        const ptr = self.api.global_lock(mem) orelse return error.GlobalLockFailed;
        defer _ = self.api.global_unlock(mem);
        const out: [*]u16 = @ptrCast(@alignCast(ptr));
        @memcpy(out[0 .. wide.len + 1], wide[0 .. wide.len + 1]);

        if (self.api.open_clipboard(self.hwnd) == 0) return error.OpenClipboardFailed;
        defer _ = self.api.close_clipboard();
        _ = self.api.empty_clipboard();
        if (self.api.set_clipboard_data(win32.CF_UNICODETEXT, mem) == null) return error.SetClipboardFailed;
    }

    pub fn readTextFromClipboard(self: *WindowsWindow, allocator: std.mem.Allocator) ![]u8 {
        if (self.api.is_clipboard_format_available(win32.CF_UNICODETEXT) == 0) return error.ClipboardEmpty;
        if (self.api.open_clipboard(self.hwnd) == 0) return error.OpenClipboardFailed;
        defer _ = self.api.close_clipboard();
        const mem = self.api.get_clipboard_data(win32.CF_UNICODETEXT) orelse return error.ClipboardEmpty;
        const ptr = self.api.global_lock(mem) orelse return error.GlobalLockFailed;
        defer _ = self.api.global_unlock(mem);
        const wptr: [*:0]const u16 = @ptrCast(@alignCast(ptr));
        const len = std.mem.len(wptr);
        return try std.unicode.utf16LeToUtf8Alloc(allocator, wptr[0..len]);
    }

    pub fn saveClientScreenshotPng(self: *WindowsWindow, path: []const u8) !void {
        const hwnd = self.hwnd orelse return error.WindowNotReady;
        var rect: win32.Rect = undefined;
        if (self.api.user32.get_client_rect(hwnd, &rect) == 0) return error.GetClientRectFailed;
        const width = @max(1, rect.right - rect.left);
        const height = @max(1, rect.bottom - rect.top);

        const window_dc = self.api.user32.get_dc(hwnd) orelse return error.GetDcFailed;
        defer _ = self.api.user32.release_dc(hwnd, window_dc);
        const memory_dc = self.api.gdi32.create_compatible_dc(window_dc) orelse return error.CreateCompatibleDcFailed;
        defer _ = self.api.gdi32.delete_dc(memory_dc);
        const bitmap: win32.HBITMAP = @ptrCast(self.api.gdi32.create_compatible_bitmap(window_dc, width, height) orelse return error.CreateBitmapFailed);
        defer _ = self.api.gdi32.delete_object(@ptrCast(bitmap));
        const previous = self.api.gdi32.select_object(memory_dc, @ptrCast(bitmap));
        defer _ = self.api.gdi32.select_object(memory_dc, previous);
        if (self.api.gdi32.bit_blt(memory_dc, 0, 0, width, height, window_dc, 0, 0, SRCCOPY) == 0) return error.BitBltFailed;

        var info = win32.BITMAPINFO{
            .bmiHeader = .{
                .biSize = @sizeOf(win32.BITMAPINFOHEADER),
                .biWidth = width,
                .biHeight = -@as(i32, @intCast(height)),
                .biPlanes = 1,
                .biBitCount = 32,
                .biCompression = win32.BI_RGB,
                .biSizeImage = @intCast(width * height * 4),
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed = 0,
                .biClrImportant = 0,
            },
            .bmiColors = .{.{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 }},
        };

        const pixel_count: usize = @intCast(width * height);
        const bgra = try self.allocator.alloc(u8, pixel_count * 4);
        defer self.allocator.free(bgra);
        if (self.api.gdi32.get_di_bits(memory_dc, bitmap, 0, @intCast(height), bgra.ptr, &info, win32.DIB_RGB_COLORS) == 0) {
            return error.GetDibitsFailed;
        }

        const rgba = try self.allocator.alloc(u8, bgra.len);
        defer self.allocator.free(rgba);
        var i: usize = 0;
        while (i < bgra.len) : (i += 4) {
            rgba[i + 0] = bgra[i + 2];
            rgba[i + 1] = bgra[i + 1];
            rgba[i + 2] = bgra[i + 0];
            rgba[i + 3] = 0xff;
        }

        const png_bytes = try png.encodeRgba8Alloc(self.allocator, @intCast(width), @intCast(height), rgba);
        defer self.allocator.free(png_bytes);

        var file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(png_bytes);
    }

    pub fn clientRect(self: *WindowsWindow) ?win32.Rect {
        const hwnd = self.hwnd orelse return null;
        var rect: win32.Rect = undefined;
        if (self.api.user32.get_client_rect(hwnd, &rect) == 0) return null;
        return rect;
    }

    pub fn drawText(self: *WindowsWindow) !void {
        const hwnd = self.hwnd orelse return;
        _ = self.paint(hwnd);
    }

    fn windowWidth(self: *const WindowsWindow) i32 {
        return self.width_px;
    }

    fn windowHeight(self: *const WindowsWindow) i32 {
        return self.height_px;
    }

    fn paint(self: *WindowsWindow, hwnd: ?win32.HWND) win32.LRESULT {
        var ps: win32.PaintStruct = undefined;
        const hdc = self.api.user32.begin_paint(hwnd, &ps);
        defer _ = self.api.user32.end_paint(hwnd, &ps);

        var rect: win32.Rect = undefined;
        _ = self.api.user32.get_client_rect(hwnd, &rect);
        const width = @max(1, rect.right - rect.left);
        const height = @max(1, rect.bottom - rect.top);
        const memory_dc = self.api.gdi32.create_compatible_dc(hdc);
        if (memory_dc == null) return 0;
        defer _ = self.api.gdi32.delete_dc(memory_dc);

        const bitmap = self.api.gdi32.create_compatible_bitmap(hdc, width, height) orelse return 0;
        defer _ = self.api.gdi32.delete_object(@ptrCast(bitmap));
        const previous = self.api.gdi32.select_object(memory_dc, @ptrCast(bitmap));
        defer _ = self.api.gdi32.select_object(memory_dc, previous);

        _ = self.api.user32.fill_rect(memory_dc, &rect, self.bg_brush);

        if (self.font) |font| {
            _ = self.api.gdi32.select_object(memory_dc, @ptrCast(font));
        }

        if (self.callbacks.on_paint) |cb| {
            var canvas = WindowsCanvas{
                .window = self,
                .hdc = memory_dc,
                .bounds = rect,
            };
            if (cb(self.callback_ctx orelse @ptrCast(self), &canvas) catch false) {
                self.paintFooter(memory_dc, rect);
                _ = self.api.gdi32.bit_blt(hdc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
                return 0;
            }
        }

        _ = self.api.gdi32.set_text_color(memory_dc, self.style.foreground_rgb);
        _ = self.api.gdi32.set_bk_mode(memory_dc, win32.TRANSPARENT);
        var text_rect = win32.Rect{
            .left = self.style.padding,
            .top = self.style.padding,
            .right = rect.right - self.style.padding,
            .bottom = rect.bottom - self.style.padding - self.footerHeight(),
        };
        _ = self.api.user32.draw_text_w(memory_dc, self.text.ptr, @intCast(self.text.len), &text_rect, win32.DT_LEFT | win32.DT_TOP | win32.DT_NOPREFIX | win32.DT_WORDBREAK | win32.DT_EXPANDTABS);
        self.paintFooter(memory_dc, rect);
        _ = self.api.gdi32.bit_blt(hdc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
        return 0;
    }

    fn dispatchPaint(self: *WindowsWindow, hwnd: ?win32.HWND) win32.LRESULT {
        return self.paint(hwnd);
    }

    fn dispatchTick(self: *WindowsWindow) void {
        if (self.callbacks.on_tick) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self)) catch {};
        }
    }

    fn dispatchChar(self: *WindowsWindow, codepoint: u21) void {
        if (self.suppress_char) {
            self.suppress_char = false;
            return;
        }
        if (self.callbacks.on_char) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self), codepoint, self.currentModifiers()) catch {};
        }
    }

    fn dispatchKeyDown(self: *WindowsWindow, vkey: u32, is_repeat: bool) void {
        const mods = self.currentModifiers();
        self.suppress_char = input_mod.suppressCharAfterKeyDown(vkey, mods);
        if (self.callbacks.on_key_down) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self), vkey, mods, is_repeat) catch {};
        }
    }

    fn dispatchKeyUp(self: *WindowsWindow, vkey: u32) void {
        if (self.callbacks.on_key_up) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self), vkey, self.currentModifiers()) catch {};
        }
    }

    fn dispatchMouseWheel(self: *WindowsWindow, delta: i16) void {
        if (self.callbacks.on_mouse_wheel) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self), delta) catch {};
        }
    }

    fn dispatchMouseEvent(self: *WindowsWindow, kind: input_mod.MouseEventKind, button: input_mod.MouseButton, client_x: i32, client_y: i32) void {
        if (self.callbacks.on_mouse_event) |cb| {
            const mods = self.currentModifiers();
            const event = input_mod.MouseEvent{
                .kind = kind,
                .button = button,
                .x = @intCast(@max(1, client_x)),
                .y = @intCast(@max(1, client_y)),
                .shift = mods.shift,
                .alt = mods.alt,
                .ctrl = mods.ctrl,
            };
            cb(self.callback_ctx orelse @ptrCast(self), event) catch {};
        }
    }

    fn dispatchResize(self: *WindowsWindow, new_width: i32, new_height: i32) void {
        if (self.callbacks.on_resize) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self), new_width, new_height) catch {};
        }
    }

    fn dispatchFocusChanged(self: *WindowsWindow, focused: bool) void {
        self.focused = focused;
        self.suppress_char = false;
        if (!focused) {
            self.mouse_buttons = .none;
            _ = self.api.user32.release_capture();
        }
        if (self.callbacks.on_focus_changed) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self), focused) catch {};
        }
        self.requestRepaint();
    }

    fn wndProc(hwnd: ?win32.HWND, message: win32.UINT, w_param: win32.WPARAM, l_param: win32.LPARAM) callconv(.winapi) win32.LRESULT {
        const self = active orelse return 0;
        return switch (message) {
            win32.WM_DESTROY => blk: {
                if (self.callbacks.on_destroy) |cb| {
                    cb(self.callback_ctx orelse @ptrCast(self)) catch {};
                }
                self.api.user32.post_quit_message(0);
                break :blk 0;
            },
            win32.WM_SETFOCUS => blk: {
                self.dispatchFocusChanged(true);
                break :blk 0;
            },
            win32.WM_KILLFOCUS => blk: {
                self.dispatchFocusChanged(false);
                break :blk 0;
            },
            win32.WM_ACTIVATE => blk: {
                const is_active = (@as(usize, @bitCast(w_param)) & 0xffff) != 0;
                self.dispatchFocusChanged(is_active);
                break :blk 0;
            },
            win32.WM_ERASEBKGND => 1,
            WM_FMUS_REPAINT => blk: {
                _ = self.api.user32.invalidate_rect(hwnd, null, 0);
                break :blk 0;
            },
            win32.WM_PAINT => self.dispatchPaint(hwnd),
            win32.WM_COMMAND => blk: {
                const command_id: u16 = @truncate(@as(usize, @bitCast(w_param)) & 0xffff);
                self.dispatchCommand(command_id);
                break :blk 0;
            },
            win32.WM_TIMER => blk: {
                self.dispatchTick();
                break :blk 0;
            },
            win32.WM_CHAR, win32.WM_SYSCHAR => blk: {
                self.dispatchChar(@intCast(w_param));
                break :blk 0;
            },
            win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN => blk: {
                const bits: usize = @bitCast(l_param);
                self.dispatchKeyDown(@intCast(w_param), ((bits >> 30) & 1) != 0);
                break :blk 0;
            },
            win32.WM_KEYUP, win32.WM_SYSKEYUP => blk: {
                self.dispatchKeyUp(@intCast(w_param));
                break :blk 0;
            },
            win32.WM_MOUSEWHEEL => blk: {
                const packed_bits: usize = @bitCast(w_param);
                const delta = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseWheel(delta);
                break :blk 0;
            },
            win32.WM_MOUSEMOVE => blk: {
                if (!self.tracking_mouse_leave) {
                    var tme = win32.TRACKMOUSEEVENT{
                        .cbSize = @sizeOf(win32.TRACKMOUSEEVENT),
                        .dwFlags = win32.TME_LEAVE,
                        .hwndTrack = hwnd,
                        .dwHoverTime = 0,
                    };
                    _ = self.api.user32.track_mouse_event(&tme);
                    self.tracking_mouse_leave = true;
                }
                const packed_bits: usize = @bitCast(l_param);
                const x = @as(i16, @bitCast(@as(u16, @truncate(packed_bits & 0xffff))));
                const y = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseEvent(.move, self.mouse_buttons, x, y);
                break :blk 0;
            },
            win32.WM_MOUSELEAVE => blk: {
                self.tracking_mouse_leave = false;
                self.mouse_buttons = .none;
                _ = self.api.user32.release_capture();
                break :blk 0;
            },
            win32.WM_LBUTTONDOWN => blk: {
                self.mouse_buttons = .left;
                _ = self.api.user32.set_capture(hwnd);
                const packed_bits: usize = @bitCast(l_param);
                const x = @as(i16, @bitCast(@as(u16, @truncate(packed_bits & 0xffff))));
                const y = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseEvent(.press, .left, x, y);
                break :blk 0;
            },
            win32.WM_LBUTTONUP => blk: {
                const packed_bits: usize = @bitCast(l_param);
                const x = @as(i16, @bitCast(@as(u16, @truncate(packed_bits & 0xffff))));
                const y = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseEvent(.release, .left, x, y);
                self.mouse_buttons = .none;
                _ = self.api.user32.release_capture();
                break :blk 0;
            },
            win32.WM_MBUTTONDOWN => blk: {
                self.mouse_buttons = .middle;
                _ = self.api.user32.set_capture(hwnd);
                const packed_bits: usize = @bitCast(l_param);
                const x = @as(i16, @bitCast(@as(u16, @truncate(packed_bits & 0xffff))));
                const y = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseEvent(.press, .middle, x, y);
                break :blk 0;
            },
            win32.WM_MBUTTONUP => blk: {
                const packed_bits: usize = @bitCast(l_param);
                const x = @as(i16, @bitCast(@as(u16, @truncate(packed_bits & 0xffff))));
                const y = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseEvent(.release, .middle, x, y);
                self.mouse_buttons = .none;
                _ = self.api.user32.release_capture();
                break :blk 0;
            },
            win32.WM_RBUTTONDOWN => blk: {
                self.mouse_buttons = .right;
                _ = self.api.user32.set_capture(hwnd);
                const packed_bits: usize = @bitCast(l_param);
                const x = @as(i16, @bitCast(@as(u16, @truncate(packed_bits & 0xffff))));
                const y = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseEvent(.press, .right, x, y);
                break :blk 0;
            },
            win32.WM_RBUTTONUP => blk: {
                const packed_bits: usize = @bitCast(l_param);
                const x = @as(i16, @bitCast(@as(u16, @truncate(packed_bits & 0xffff))));
                const y = @as(i16, @bitCast(@as(u16, @truncate((packed_bits >> 16) & 0xffff))));
                self.dispatchMouseEvent(.release, .right, x, y);
                self.mouse_buttons = .none;
                _ = self.api.user32.release_capture();
                break :blk 0;
            },
            win32.WM_SIZE => blk: {
                const packed_bits: usize = @bitCast(l_param);
                const new_width = @as(i32, @intCast(packed_bits & 0xffff));
                const new_height = @as(i32, @intCast((packed_bits >> 16) & 0xffff));
                self.dispatchResize(new_width, new_height);
                break :blk self.api.user32.def_window_proc_w(hwnd, message, w_param, l_param);
            },
            else => self.api.user32.def_window_proc_w(hwnd, message, w_param, l_param),
        };
    }

    fn currentModifiers(self: *WindowsWindow) KeyModifiers {
        const right_alt = self.keyDown(win32.VK_RMENU);
        const left_ctrl = self.keyDown(win32.VK_LCONTROL);
        const right_ctrl = self.keyDown(win32.VK_RCONTROL);
        const alt_gr = right_alt and left_ctrl and !right_ctrl;

        return .{
            .shift = self.keyDown(win32.VK_SHIFT),
            .alt = self.keyDown(win32.VK_MENU),
            .ctrl = self.keyDown(win32.VK_CONTROL) and !alt_gr,
            .super_key = self.keyDown(win32.VK_LWIN) or self.keyDown(win32.VK_RWIN),
        };
    }

    fn keyDown(self: *WindowsWindow, vkey: win32.INT) bool {
        const state_bits: u16 = @bitCast(self.api.user32.get_key_state(vkey));
        return (state_bits & 0x8000) != 0;
    }

    fn measureFontMetrics(self: *WindowsWindow) FontMetrics {
        const dc = self.api.gdi32.create_compatible_dc(null);
        if (dc == null) return .{};
        defer _ = self.api.gdi32.delete_dc(dc);

        const previous = self.api.gdi32.select_object(dc, @ptrCast(self.font));
        defer _ = self.api.gdi32.select_object(dc, previous);

        var tm: win32.TEXTMETRICW = undefined;
        if (self.api.gdi32.get_text_metrics_w(dc, &tm) == 0) return .{};

        const probe: [2]u16 = .{ 'M', 0 };
        var size: win32.SIZE = .{ .cx = tm.tmAveCharWidth, .cy = tm.tmHeight };
        _ = self.api.gdi32.get_text_extent_point32_w(dc, probe[0..1].ptr, 1, &size);

        return .{
            .cell_width_px = @max(1, size.cx),
            .cell_height_px = @max(1, tm.tmHeight),
            .baseline_px = @max(1, tm.tmAscent),
        };
    }

    fn dispatchCommand(self: *WindowsWindow, command_id: u16) void {
        switch (command_id) {
            CMD_TOGGLE_FULLSCREEN => self.toggleFullscreen() catch {},
            CMD_TOGGLE_ZEN => self.toggleZen() catch {},
            CMD_EXIT => {
                if (self.hwnd) |hwnd| {
                    _ = self.api.user32.destroy_window(hwnd);
                }
            },
            else => {},
        }
        if (self.callbacks.on_command) |cb| {
            cb(self.callback_ctx orelse @ptrCast(self), command_id) catch {};
        }
    }

    fn baseWindowStyle(self: *const WindowsWindow) isize {
        const style: win32.DWORD = if (self.zen)
            (win32.WS_VISIBLE | win32.WS_POPUP | win32.WS_THICKFRAME | win32.WS_MINIMIZEBOX | win32.WS_MAXIMIZEBOX)
        else
            (win32.WS_VISIBLE | win32.WS_OVERLAPPEDWINDOW);
        return @intCast(style);
    }

    fn applyMenuState(self: *WindowsWindow) !void {
        const hwnd = self.hwnd orelse return;
        const show_menu = self.show_menu and !self.zen and !self.fullscreen;
        if (show_menu) {
            if (self.menu == null) {
                self.menu = self.api.user32.create_menu() orelse return error.CreateMenuFailed;
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_STRING, CMD_SCREENSHOT, self.menu_label_screenshot.?.ptr);
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_STRING, CMD_COMMAND_PALETTE, self.menu_label_palette.?.ptr);
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_STRING, CMD_THEME_PICKER, self.menu_label_theme.?.ptr);
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_SEPARATOR, 0, null);
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_STRING, CMD_TOGGLE_FULLSCREEN, self.menu_label_fullscreen.?.ptr);
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_STRING, CMD_TOGGLE_ZEN, self.menu_label_zen.?.ptr);
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_SEPARATOR, 0, null);
                _ = self.api.user32.append_menu_w(self.menu, win32.MF_STRING, CMD_EXIT, self.menu_label_exit.?.ptr);
            }
            _ = self.api.user32.set_menu(hwnd, self.menu);
        } else {
            _ = self.api.user32.set_menu(hwnd, null);
        }
        _ = self.api.user32.draw_menu_bar(hwnd);
    }

    fn loadWindowIcon(self: *WindowsWindow, path: [:0]u16) void {
        const hwnd = self.hwnd orelse return;
        const icon = self.api.user32.load_image_w(null, path.ptr, win32.IMAGE_ICON, 0, 0, win32.LR_LOADFROMFILE | win32.LR_DEFAULTSIZE) orelse return;
        const icon_param: win32.LPARAM = @intCast(@intFromPtr(icon));
        _ = self.api.user32.send_message_w(hwnd, win32.WM_SETICON, win32.ICON_SMALL, icon_param);
        _ = self.api.user32.send_message_w(hwnd, win32.WM_SETICON, win32.ICON_BIG, icon_param);
    }

    fn paintFooter(self: *WindowsWindow, hdc: win32.HDC, rect: win32.Rect) void {
        if (!self.show_footer or self.zen or self.footer_text.len == 0) return;
        const footer_h = self.footerHeight();
        if (footer_h <= 0) return;
        const top = rect.bottom - footer_h;
        var footer_rect = win32.Rect{ .left = 0, .top = top, .right = rect.right, .bottom = rect.bottom };
        const bg = self.api.gdi32.create_solid_brush(self.style.background_rgb);
        if (bg) |brush| {
            defer _ = self.api.gdi32.delete_object(@ptrCast(brush));
            _ = self.api.user32.fill_rect(hdc, &footer_rect, brush);
        }
        _ = self.api.gdi32.set_text_color(hdc, self.style.foreground_rgb);
        _ = self.api.gdi32.set_bk_mode(hdc, win32.TRANSPARENT);
        if (self.font) |font| {
            const previous = self.api.gdi32.select_object(hdc, @ptrCast(font));
            defer _ = self.api.gdi32.select_object(hdc, previous);
            footer_rect.left = self.style.padding;
            footer_rect.right -= self.style.padding;
            footer_rect.top += @max(2, @divFloor(footer_h - self.font_metrics.cell_height_px, 2));
            _ = self.api.user32.draw_text_w(hdc, self.footer_text.ptr, @intCast(self.footer_text.len), &footer_rect, win32.DT_LEFT | win32.DT_TOP | win32.DT_NOPREFIX);
        }
    }

    fn monitorIndex(self: *WindowsWindow, target: win32.HMONITOR) u32 {
        const Ctx = struct {
            target: win32.HMONITOR,
            index: u32 = 0,
            found: u32 = 0,
        };
        var ctx = Ctx{ .target = target };
        const enum_proc = struct {
            fn call(monitor: win32.HMONITOR, _: win32.HDC, _: ?*win32.Rect, data: win32.LPARAM) callconv(.winapi) win32.BOOL {
                const ptr: *Ctx = @ptrFromInt(@as(usize, @intCast(data)));
                ptr.index += 1;
                if (monitor == ptr.target) {
                    ptr.found = ptr.index;
                    return 0;
                }
                return 1;
            }
        }.call;
        _ = self.api.user32.enum_display_monitors(null, null, enum_proc, @intCast(@intFromPtr(&ctx)));
        return if (ctx.found == 0) 1 else ctx.found;
    }

    fn createFontVariant(self: *WindowsWindow, face_name: [*:0]const u16, height: i32, bold: bool, italic: bool, monospace: bool) win32.HFONT {
        return self.api.gdi32.create_font_w(
            height,
            0,
            0,
            0,
            if (bold) win32.FW_BOLD else win32.FW_NORMAL,
            @intFromBool(italic),
            0,
            0,
            win32.DEFAULT_CHARSET,
            win32.OUT_OUTLINE_PRECIS,
            win32.CLIP_DEFAULT_PRECIS,
            win32.CLEARTYPE_QUALITY,
            if (monospace) win32.FIXED_PITCH | win32.FF_MODERN else 0,
            face_name,
        );
    }
};

fn freeWideZ(allocator: std.mem.Allocator, value: [:0]u16) void {
    allocator.free(value[0 .. value.len + 1]);
}

const WindowsCanvas = struct {
    window: *WindowsWindow,
    hdc: win32.HDC,
    bounds: win32.Rect,

    pub fn fillRect(self: *WindowsCanvas, x: i32, y: i32, width: i32, height: i32, rgb: u32) void {
        const brush = self.window.api.gdi32.create_solid_brush(rgb);
        if (brush == null) return;
        defer _ = self.window.api.gdi32.delete_object(@ptrCast(brush));

        var rect = win32.Rect{
            .left = x,
            .top = y,
            .right = x + width,
            .bottom = y + height,
        };
        _ = self.window.api.user32.fill_rect(self.hdc, &rect, brush);
    }

    pub fn drawText(self: *WindowsCanvas, x: i32, y: i32, width: i32, text: []const u16, rgb: u32, emoji_font: bool, attrs: TextAttrs) void {
        _ = self.window.api.gdi32.set_text_color(self.hdc, rgb);
        _ = self.window.api.gdi32.set_bk_mode(self.hdc, win32.TRANSPARENT);
        const font = self.pickFont(text, emoji_font, attrs);
        const previous = self.window.api.gdi32.select_object(self.hdc, @ptrCast(font));
        defer _ = self.window.api.gdi32.select_object(self.hdc, previous);
        var rect = win32.Rect{
            .left = x,
            .top = y,
            .right = x + width,
            .bottom = y + self.window.font_metrics.cell_height_px,
        };
        _ = self.window.api.gdi32.ext_text_out_w(self.hdc, x, y, win32.ETO_CLIPPED, &rect, text.ptr, @intCast(text.len), null);
    }

    fn pickFont(self: *WindowsCanvas, text: []const u16, emoji_hint: bool, attrs: TextAttrs) win32.HFONT {
        if (emoji_hint) {
            if (self.window.emoji_font) |font| {
                if (self.fontSupportsText(font, text)) return font;
            }
        }
        if (self.primaryFont(attrs)) |font| {
            if (self.fontSupportsText(font, text)) return font;
        }
        for (self.window.fallback_fonts) |font| {
            if (font) |f| {
                if (self.fontSupportsText(f, text)) return f;
            }
        }
        return self.window.emoji_font orelse self.window.font;
    }

    fn primaryFont(self: *WindowsCanvas, attrs: TextAttrs) ?win32.HFONT {
        if (attrs.bold and attrs.italic) return self.window.font_bold_italic;
        if (attrs.bold) return self.window.font_bold;
        if (attrs.italic) return self.window.font_italic;
        return self.window.font;
    }

    fn fontSupportsText(self: *WindowsCanvas, font: win32.HFONT, text: []const u16) bool {
        if (text.len == 0) return true;
        const previous = self.window.api.gdi32.select_object(self.hdc, @ptrCast(font));
        defer _ = self.window.api.gdi32.select_object(self.hdc, previous);
        var glyphs: [8]u16 = [_]u16{0} ** 8;
        if (text.len > glyphs.len) return false;
        _ = self.window.api.gdi32.get_glyph_indices_w(self.hdc, text.ptr, @intCast(text.len), &glyphs, win32.GGI_MARK_NONEXISTING_GLYPHS);
        for (glyphs[0..text.len]) |glyph| {
            if (glyph == 0xFFFF) return false;
        }
        return true;
    }
};

test "window stubs or types compile" {
    try std.testing.expect(@sizeOf(TextStyle) > 0);
}
