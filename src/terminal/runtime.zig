const builtin = @import("builtin");
const std = @import("std");
const cell_mod = @import("cell.zig");
const copy_mode_mod = @import("copy_mode.zig");
const input_mod = @import("input.zig");
const overlay_mod = @import("overlay.zig");
const paint_mod = @import("paint.zig");
const pane_mod = @import("pane.zig");
const publish_mod = @import("publish.zig");
const shell_mod = @import("shell.zig");
const key_encode = @import("key_encode.zig");
const state_mod = @import("state.zig");
const platform = @import("../platform.zig");
const debug_mod = @import("debug.zig");
const win32 = @import("../platform/win32.zig");
const ThemeRgb = @TypeOf((state_mod.ThemeColors{ .fg = undefined }).fg);

const SelectionPoint = struct {
    row: usize,
    col: usize,
};

const ClickState = struct {
    row: usize,
    col: usize,
    at_ms: i64,
    count: u8,
};

pub const Config = struct {
    pub const StartupInputMode = enum {
        direct_pty,
        window_events,
    };

    title: []const u8 = "FMUS Terminal",
    class_name: []const u8 = "FMUSTerminalWindow",
    rows: usize = 30,
    cols: usize = 110,
    width: i32 = 1120,
    height: i32 = 760,
    icon_path: ?[]const u8 = null,
    show_menu: bool = true,
    show_footer: bool = true,
    footer_height_px: i32 = 28,
    poll_interval_ms: u32 = 16,
    cursor_blink_ms: u32 = 530,
    cwd: ?[]const u8 = null,
    cell_width_px: i32 = 11,
    cell_height_px: i32 = 22,
    padding_px: i32 = 24,
    window_style: platform.TextStyle = .{},
    paint_metrics: paint_mod.Metrics = .{},
    paint_theme: paint_mod.Theme = .{ .cursor_shape = .block },
    startup_input: []const u8 = "",
    startup_input_delay_ms: u32 = 120,
    startup_input_mode: StartupInputMode = .direct_pty,
    debug_log_path: ?[]const u8 = null,
};

pub const Runtime = if (builtin.os.tag == .windows) WindowsRuntime else StubRuntime;

const StubRuntime = struct {
    pub fn init(_: std.mem.Allocator, _: Config) !StubRuntime {
        return error.UnsupportedPlatform;
    }

    pub fn deinit(_: *StubRuntime) void {}
    pub fn spawn(_: *StubRuntime, _: []const []const u8) !void {
        return error.UnsupportedPlatform;
    }
    pub fn run(_: *StubRuntime) !void {
        return error.UnsupportedPlatform;
    }
};

const WindowsRuntime = struct {
    allocator: std.mem.Allocator,
    config: Config,
    pane: pane_mod.Pane,
    frames: [2]publish_mod.Frame,
    active_frame: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    window: platform.Window,
    scratch: std.ArrayList(u8),
    last_title: std.ArrayList(u8),
    last_footer: std.ArrayList(u8),
    status_message: std.ArrayList(u8),
    status_until_ms: i64 = 0,
    mutex: std.Thread.Mutex = .{},
    poll_thread: ?std.Thread = null,
    stop_poll: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    child_exit_seen: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    repaint_pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    tick_count: usize = 0,
    cursor_blink_on: bool = true,
    debug_log_file: ?std.fs.File = null,
    last_mouse_x: i32 = 1,
    last_mouse_y: i32 = 1,
    selection_anchor: ?SelectionPoint = null,
    selection_head: ?SelectionPoint = null,
    last_click: ?ClickState = null,
    overlay: overlay_mod.State = .{},
    copy_mode: copy_mode_mod.State = .{},

    pub fn init(allocator: std.mem.Allocator, config: Config) !WindowsRuntime {
        debug_mod.reset();
        var pane = try pane_mod.Pane.init(allocator, .{
            .rows = config.rows,
            .cols = config.cols,
            .cwd = config.cwd,
        });
        errdefer pane.deinit();
        pane.engine.state.theme_colors = .{
            .fg = colorFromColorref(config.paint_theme.foreground_rgb),
            .bg = colorFromColorref(config.paint_theme.background_rgb),
            .cursor = colorFromColorref(config.paint_theme.cursor_rgb),
        };

        var runtime = WindowsRuntime{
            .allocator = allocator,
            .config = config,
            .pane = pane,
            .frames = undefined,
            .window = undefined,
            .scratch = .empty,
            .last_title = .empty,
            .last_footer = .empty,
            .status_message = .empty,
            .tick_count = 0,
            .cursor_blink_on = true,
            .debug_log_file = null,
        };
        errdefer runtime.status_message.deinit(allocator);
        errdefer runtime.last_footer.deinit(allocator);
        errdefer runtime.last_title.deinit(allocator);
        errdefer runtime.scratch.deinit(allocator);
        runtime.frames[0] = try publish_mod.Frame.init(allocator, config.rows, config.cols);
        errdefer runtime.frames[0].deinit();
        runtime.frames[1] = try publish_mod.Frame.init(allocator, config.rows, config.cols);
        errdefer runtime.frames[1].deinit();

        if (config.debug_log_path) |path| {
            runtime.debug_log_file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        }

        runtime.window = try platform.Window.init(allocator, .{
            .title = config.title,
            .class_name = config.class_name,
            .width = config.width,
            .height = config.height,
            .icon_path = config.icon_path,
            .text = "",
            .style = config.window_style,
            .show_menu = config.show_menu,
            .show_footer = config.show_footer,
            .footer_height_px = config.footer_height_px,
            .timer_interval_ms = config.poll_interval_ms,
            .callbacks = .{
                .on_paint = onPaint,
                .on_tick = onTick,
                .on_char = onChar,
                .on_key_down = onKeyDown,
                .on_key_up = onKeyUp,
                .on_mouse_wheel = onMouseWheel,
                .on_mouse_event = onMouseEvent,
                .on_resize = onResize,
                .on_focus_changed = onFocusChanged,
                .on_command = onCommand,
                .on_destroy = onDestroy,
            },
            .callback_ctx = null,
        });
        runtime.applyMeasuredFontMetrics();
        try runtime.pane.resize(runtime.computeRows(config.height), runtime.computeCols(config.width));
        try runtime.refreshPublishedFrameLocked(true);

        return runtime;
    }

    pub fn deinit(self: *WindowsRuntime) void {
        if (self.debug_log_file) |file| file.close();
        self.window.deinit();
        self.stop_poll.store(true, .seq_cst);
        if (self.poll_thread) |thread| thread.join();
        self.frames[0].deinit();
        self.frames[1].deinit();
        self.status_message.deinit(self.allocator);
        self.last_footer.deinit(self.allocator);
        self.last_title.deinit(self.allocator);
        self.scratch.deinit(self.allocator);
        self.pane.deinit();
    }

    pub fn spawn(self: *WindowsRuntime, argv: []const []const u8) !void {
        self.window.setCallbackContext(@ptrCast(self));
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.pane.spawn(argv);
        try self.refreshWindowStateLocked(true);
        try self.ensurePollThread();
    }

    pub fn spawnDefaultShell(self: *WindowsRuntime) !void {
        var launch = try shell_mod.launchDefault(self.allocator);
        defer launch.deinit();
        self.window.setCallbackContext(@ptrCast(self));
        self.mutex.lock();
        try self.pane.spawn(launch.argv);
        self.mutex.unlock();
        if (launch.prompt_kick_input.len != 0) {
            std.Thread.sleep(40 * std.time.ns_per_ms);
            try self.pane.sendInput(launch.prompt_kick_input);
        }
        if (launch.bootstrap_input.len != 0) {
            std.Thread.sleep(60 * std.time.ns_per_ms);
            try self.pane.sendInput(launch.bootstrap_input);
        }
        try self.waitForInitialShellPaint();
        if (self.config.startup_input.len != 0) {
            std.Thread.sleep(self.config.startup_input_delay_ms * std.time.ns_per_ms);
            switch (self.config.startup_input_mode) {
                .direct_pty => try self.pane.sendInput(self.config.startup_input),
                .window_events => try self.injectWindowInput(self.config.startup_input),
            }
            self.debugLog("startup input: {s}", .{self.config.startup_input});
        }
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.refreshWindowStateLocked(true);
        try self.ensurePollThread();
    }

    pub fn run(self: *WindowsRuntime) !void {
        self.window.setCallbackContext(@ptrCast(self));
        try self.window.run();
    }

    fn onTick(ctx: *anyopaque) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.tick_count += 1;
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.syncWindowTitle();
        try self.syncFooter();
        if (self.config.cursor_blink_ms != 0) {
            const ticks_per_toggle = @max(1, @divFloor(self.config.cursor_blink_ms, self.config.poll_interval_ms));
            if (self.tick_count % ticks_per_toggle == 0) {
                self.cursor_blink_on = !self.cursor_blink_on;
                self.pane.engine.state.cursor.visible = self.cursor_blink_on;
                self.publishCursorLocked();
                self.requestRepaint();
            }
        }
    }

    fn onPaint(ctx: *anyopaque, canvas: *platform.Canvas) !bool {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        _ = self.repaint_pending.swap(false, .acq_rel);
        self.debugLog("paint begin", .{});
        const frame = self.activeFrame();
        paint_mod.paintFrame(canvas, frame, self.config.paint_metrics, self.config.paint_theme);
        if (self.mutex.tryLock()) {
            defer self.mutex.unlock();
            if (self.selection_anchor != null and self.selection_head != null and self.pane.engine.state.mouse_tracking == .off) {
                const anchor = self.selection_anchor.?;
                const head = self.selection_head.?;
                paint_mod.paintSelectionFrame(canvas, frame, self.config.paint_metrics, self.config.paint_theme, .{
                    .start_row = anchor.row,
                    .start_col = anchor.col,
                    .end_row = head.row,
                    .end_col = head.col,
                });
            }
            if (self.copy_mode.isVisual()) {
                if (self.copy_mode.selection(frame.cols)) |sel| {
                    paint_mod.paintSelectionFrame(canvas, frame, self.config.paint_metrics, self.config.paint_theme, .{
                        .start_row = sel.start.row,
                        .start_col = sel.start.col,
                        .end_row = sel.end.row,
                        .end_col = sel.end.col,
                    });
                }
            }
            overlay_mod.paint(canvas, self.config.paint_metrics, self.config.paint_theme, self.overlay, frame.rows, frame.cols);
        }
        self.debugLog("paint end", .{});
        return true;
    }

    fn onChar(ctx: *anyopaque, codepoint: u21, mods: platform.KeyModifiers) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        const event = input_mod.charEvent(codepoint, mods) orelse return;
        self.debugLog("char cp={d}", .{codepoint});
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.overlay.active) return;
        if (self.copy_mode.isActive()) return;
        self.clearSelection();
        try self.pane.sendKey(event);
        self.cursor_blink_on = true;
        self.pane.engine.state.cursor.visible = true;
        self.pane.scrollViewportToBottom();
    }

    fn onKeyDown(ctx: *anyopaque, vkey: u32, mods: platform.KeyModifiers, is_repeat: bool) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        switch (vkey) {
            win32.VK_F10, win32.VK_F11, win32.VK_F12 => {
                try self.handleTopLevelFunctionKey(vkey);
                return;
            },
            else => {},
        }
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.overlay.active) {
            if (try self.handleOverlayKey(vkey, mods)) return;
        }
        if (self.copy_mode.isActive()) {
            if (try self.handleCopyModeKey(vkey, mods)) return;
        }
        if (mods.ctrl and mods.shift and !mods.alt and !mods.super_key) {
            switch (vkey) {
                'C' => {
                    try self.copySelectionToClipboard();
                    return;
                },
                'V' => {
                    try self.pasteClipboard();
                    return;
                },
                else => {},
            }
        }
        if (mods.ctrl and !mods.shift and !mods.alt and !mods.super_key and vkey == 'P') {
            self.overlay.open(.command_palette);
            self.requestRepaint();
            return;
        }
        if (mods.ctrl and !mods.shift and !mods.alt and !mods.super_key and vkey == 'Y') {
            self.copy_mode.enter(self.pane.engine.state.cursor.row, self.pane.engine.state.cursor.col);
            self.requestRepaint();
            return;
        }
        if (mods.ctrl and !mods.shift and !mods.alt and !mods.super_key and vkey == 'T') {
            self.overlay.open(.theme_picker);
            self.requestRepaint();
            return;
        }
        switch (vkey) {
            0x21 => {
                self.pane.scrollViewportUp(self.pane.engine.state.rowCount() / 2 + 1);
                try self.refreshPublishedFrameLocked(true);
                self.requestRepaint();
                return;
            },
            0x22 => {
                self.pane.scrollViewportDown(self.pane.engine.state.rowCount() / 2 + 1);
                try self.refreshPublishedFrameLocked(true);
                self.requestRepaint();
                return;
            },
            0x24 => {
                if (self.pane.engine.state.viewport_offset > 0) {
                    self.pane.scrollViewportUp(self.pane.engine.state.scrollbackCount());
                    try self.refreshPublishedFrameLocked(true);
                    self.requestRepaint();
                    return;
                }
            },
            0x23 => {
                if (self.pane.engine.state.viewport_offset > 0) {
                    self.pane.scrollViewportToBottom();
                    try self.refreshPublishedFrameLocked(true);
                    self.requestRepaint();
                    return;
                }
            },
            else => {},
        }
        if (input_mod.keyEventFromVKey(vkey, mods)) |event| {
            var ev = event;
            if (is_repeat) ev.event_type = .repeat;
            self.debugLog("key vkey=0x{x} mods={d}{d}{d}{d} seq_len={d}", .{
                vkey,
                @intFromBool(mods.shift),
                @intFromBool(mods.alt),
                @intFromBool(mods.ctrl),
                @intFromBool(mods.super_key),
                1,
            });
            self.clearSelection();
            try self.pane.sendKey(ev);
            self.cursor_blink_on = true;
            self.pane.engine.state.cursor.visible = true;
            self.pane.scrollViewportToBottom();
        }
    }

    fn handleTopLevelFunctionKey(self: *WindowsRuntime, vkey: u32) !void {
        switch (vkey) {
            win32.VK_F10 => {
                const path = try self.screenshotPathAlloc();
                defer self.allocator.free(path);
                try self.window.saveClientScreenshotPng(path);
                self.mutex.lock();
                defer self.mutex.unlock();
                const base = std.fs.path.basename(path);
                try self.setStatusMessageFmt("Saved {s}", .{base});
                self.debugLog("screenshot={s}", .{path});
                self.requestRepaint();
                return;
            },
            win32.VK_F11 => try self.handleWindowChromeToggle(.fullscreen),
            win32.VK_F12 => try self.handleWindowChromeToggle(.zen),
            else => {},
        }
    }

    const ChromeToggle = enum {
        fullscreen,
        zen,
    };

    fn handleWindowChromeToggle(self: *WindowsRuntime, which: ChromeToggle) !void {
        switch (which) {
            .fullscreen => try self.window.toggleFullscreen(),
            .zen => try self.window.toggleZen(),
        }
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.reflowToCurrentClientSize();
        try self.refreshWindowStateLocked(true);
        self.requestRepaint();
    }

    fn onKeyUp(ctx: *anyopaque, vkey: u32, mods: platform.KeyModifiers) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        if ((self.pane.engine.state.kittyFlags() & key_encode.KITTY_EVENT_TYPES) == 0) return;
        if (input_mod.keyEventFromVKey(vkey, mods)) |event| {
            var ev = event;
            ev.event_type = .release;
            try self.pane.sendKey(ev);
        }
    }

    fn onResize(ctx: *anyopaque, width: i32, height: i32) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        const cols = self.computeCols(width);
        const rows = self.computeRows(height);
        try self.pane.resize(rows, cols);
        try self.refreshWindowStateLocked(true);
        self.requestRepaint();
    }

    fn onMouseWheel(ctx: *anyopaque, delta: i16) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.overlay.active) {
            if (delta > 0) self.overlay.movePrev() else if (delta < 0) self.overlay.moveNext();
            self.requestRepaint();
            return;
        }
        if (try self.sendWheelToPty(delta)) {
            self.cursor_blink_on = true;
            self.pane.engine.state.cursor.visible = true;
            return;
        }
        const line_count = @max(1, self.pane.engine.state.rowCount() / 6);
        if (delta > 0) {
            self.pane.scrollViewportUp(line_count);
        } else if (delta < 0) {
            self.pane.scrollViewportDown(line_count);
        }
        try self.refreshPublishedFrameLocked(true);
        self.requestRepaint();
    }

    fn onMouseEvent(ctx: *anyopaque, ev: input_mod.MouseEvent) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        self.last_mouse_x = ev.x;
        self.last_mouse_y = ev.y;
        if (self.overlay.active) return;
        if (self.pane.engine.state.mouse_tracking == .off or !self.pane.engine.state.mouse_sgr) {
            try self.handleLocalSelection(ev);
            return;
        }
        var seq_buf: [64]u8 = undefined;
        const terminal_ev = input_mod.MouseEvent{
            .kind = ev.kind,
            .button = ev.button,
            .x = self.mouseColFromClient(@intCast(ev.x)),
            .y = self.mouseRowFromClient(@intCast(ev.y)),
            .shift = ev.shift,
            .alt = ev.alt,
            .ctrl = ev.ctrl,
        };
        const seq = input_mod.encodeMouse(self.pane.engine.state.mouse_tracking, self.pane.engine.state.mouse_sgr, terminal_ev, &seq_buf);
        if (seq.len == 0) return;
        try self.pane.sendInput(seq);
        self.cursor_blink_on = true;
        self.pane.engine.state.cursor.visible = true;
    }

    fn onDestroy(ctx: *anyopaque) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.debugLog("window destroy childExited={any} exit_code={any}", .{
            self.pane.childExited(),
            self.pane.ptyExitCode(),
        });
    }

    fn onFocusChanged(ctx: *anyopaque, focused: bool) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.cursor_blink_on = true;
        self.mutex.lock();
        defer self.mutex.unlock();
        self.pane.engine.state.cursor.visible = true;
        try self.refreshPublishedFrameLocked(true);
        self.requestRepaint();
        self.debugLog("focus={any}", .{focused});
    }

    fn onCommand(ctx: *anyopaque, command_id: u16) !void {
        const self: *WindowsRuntime = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        switch (command_id) {
            platform.window.CMD_SCREENSHOT => {
                const path = try self.screenshotPathAlloc();
                defer self.allocator.free(path);
                try self.window.saveClientScreenshotPng(path);
                try self.setStatusMessageFmt("Saved {s}", .{std.fs.path.basename(path)});
            },
            platform.window.CMD_COMMAND_PALETTE => self.overlay.open(.command_palette),
            platform.window.CMD_THEME_PICKER => self.overlay.open(.theme_picker),
            else => return,
        }
        self.requestRepaint();
    }

    fn refreshWindowStateLocked(self: *WindowsRuntime, force_full_publish: bool) !void {
        try self.refreshPublishedFrameLocked(force_full_publish);
    }

    fn refreshPublishedFrameLocked(self: *WindowsRuntime, force_full_publish: bool) !void {
        const current = self.active_frame.load(.acquire);
        const next: u8 = if (current == 0) 1 else 0;
        const frame = &self.frames[next];
        if (force_full_publish or self.pane.engine.state.force_full_publish or !self.pane.engine.state.dirty.any()) {
            try publish_mod.publishAll(frame, &self.pane.engine.state);
        } else {
            try publish_mod.publishDirty(frame, &self.pane.engine.state, &self.pane.engine.state.dirty);
        }
        self.pane.engine.state.force_full_publish = false;
        self.pane.engine.state.dirty.clear();
        self.active_frame.store(next, .release);
    }

    fn publishCursorLocked(self: *WindowsRuntime) void {
        const current = self.active_frame.load(.acquire);
        const next: u8 = if (current == 0) 1 else 0;
        self.frames[next].resize(self.frames[current].rows, self.frames[current].cols) catch return;
        @memcpy(self.frames[next].cells, self.frames[current].cells);
        @memcpy(self.frames[next].wrapped, self.frames[current].wrapped);
        self.frames[next].cursor = self.frames[current].cursor;
        self.frames[next].theme_colors = self.frames[current].theme_colors;
        publish_mod.publishCursor(&self.frames[next], &self.pane.engine.state);
        self.active_frame.store(next, .release);
    }

    fn computeCols(self: *const WindowsRuntime, width_px: i32) usize {
        const usable = @max(1, width_px - (self.config.padding_px * 2));
        return @max(1, @as(usize, @intCast(@divFloor(usable, @max(1, self.config.cell_width_px)))));
    }

    fn computeRows(self: *const WindowsRuntime, height_px: i32) usize {
        const usable = @max(1, height_px - (self.config.padding_px * 2) - self.window.footerHeight());
        return @max(1, @as(usize, @intCast(@divFloor(usable, @max(1, self.config.cell_height_px)))));
    }

    fn reflowToCurrentClientSize(self: *WindowsRuntime) !void {
        const rect = self.window.clientRect() orelse return;
        const width = rect.right - rect.left;
        const height = rect.bottom - rect.top;
        try self.pane.resize(self.computeRows(height), self.computeCols(width));
    }

    fn syncFooter(self: *WindowsRuntime) !void {
        if (self.status_until_ms > std.time.milliTimestamp() and self.status_message.items.len != 0) {
            try self.setFooterCached(self.status_message.items);
            return;
        }
        const m = self.window.metrics();
        var buf: [256]u8 = undefined;
        const width = m.client_rect.right - m.client_rect.left;
        const height = m.client_rect.bottom - m.client_rect.top;
        const window_x = m.window_rect.left;
        const window_y = m.window_rect.top;
        const monitor_w = m.monitor_rect.right - m.monitor_rect.left;
        const monitor_h = m.monitor_rect.bottom - m.monitor_rect.top;
        const cursor_row = self.pane.engine.state.cursor.row + 1;
        const cursor_col = self.pane.engine.state.cursor.col + 1;
        const free_gb = @as(f64, @floatFromInt(m.free_disk_bytes)) / 1024.0 / 1024.0 / 1024.0;
        const mode_text = if (self.overlay.active)
            "overlay"
        else if (self.copy_mode.isActive())
            "copy"
        else if (self.pane.engine.state.viewport_offset != 0)
            "scroll"
        else
            "live";
        const text = try std.fmt.bufPrint(&buf, "mode {s}  term {d}x{d}  cursor {d},{d}  view {d}  win {d},{d} {d}x{d}  screen {d}x{d}  monitor #{d} {d}x{d}  free C: {d:.1} GB  F10 shot  F11 fullscreen  F12 zen", .{
            mode_text,
            self.pane.engine.state.colCount(),
            self.pane.engine.state.rowCount(),
            cursor_col,
            cursor_row,
            self.pane.engine.state.viewport_offset,
            window_x,
            window_y,
            width,
            height,
            m.screen_width_px,
            m.screen_height_px,
            m.monitor_index,
            monitor_w,
            monitor_h,
            free_gb,
        });
        try self.setFooterCached(text);
    }

    fn sendWheelToPty(self: *WindowsRuntime, delta: i16) !bool {
        if (self.pane.engine.state.mouse_tracking == .off or !self.pane.engine.state.mouse_sgr) return false;
        var seq_buf: [64]u8 = undefined;
        const ev = input_mod.MouseEvent{
            .kind = if (delta > 0) .scroll_up else .scroll_down,
            .button = .none,
            .x = self.mouseColFromClient(self.last_mouse_x),
            .y = self.mouseRowFromClient(self.last_mouse_y),
        };
        const seq = input_mod.encodeMouse(self.pane.engine.state.mouse_tracking, self.pane.engine.state.mouse_sgr, ev, &seq_buf);
        if (seq.len == 0) return false;
        try self.pane.sendInput(seq);
        return true;
    }

    fn handleLocalSelection(self: *WindowsRuntime, ev: input_mod.MouseEvent) !void {
        switch (ev.kind) {
            .press => if (ev.button == .left) {
                const point = self.selectionPoint(ev) orelse return;
                const click_count = self.registerClick(point);
                if (ev.shift and self.selection_anchor != null) {
                    self.selection_head = point;
                } else switch (click_count) {
                    2 => self.selectWordAt(point),
                    3 => self.selectRowAt(point),
                    else => {
                        self.selection_anchor = point;
                        self.selection_head = point;
                    },
                }
                self.requestRepaint();
            },
            .move => {
                if (ev.button == .left and self.selection_anchor != null) {
                    if (self.selectionPoint(ev)) |point| {
                        self.selection_head = point;
                        self.requestRepaint();
                    }
                }
            },
            .release => {
                if (ev.button == .left and self.selection_anchor != null) {
                    if (self.selectionPoint(ev)) |point| {
                        self.selection_head = point;
                        self.requestRepaint();
                    }
                }
            },
            else => {},
        }
    }

    fn selectionPoint(self: *const WindowsRuntime, ev: input_mod.MouseEvent) ?SelectionPoint {
        const col = self.mouseColFromClient(@intCast(ev.x));
        const row = self.mouseRowFromClient(@intCast(ev.y));
        return .{ .row = row - 1, .col = col - 1 };
    }

    fn registerClick(self: *WindowsRuntime, point: SelectionPoint) u8 {
        const now = std.time.milliTimestamp();
        const within_time = if (self.last_click) |click| (now - click.at_ms) <= 400 else false;
        const same_cell = if (self.last_click) |click| click.row == point.row and click.col == point.col else false;
        const count: u8 = if (within_time and same_cell)
            @min(3, (self.last_click.?.count + 1))
        else
            1;
        self.last_click = .{
            .row = point.row,
            .col = point.col,
            .at_ms = now,
            .count = count,
        };
        return count;
    }

    fn selectWordAt(self: *WindowsRuntime, point: SelectionPoint) void {
        const frame = self.activeFrame();
        if (point.row >= frame.rows or point.col >= frame.cols) return;
        var start = point.col;
        var end = point.col;
        while (start > 0 and isWordCell(frame.cell(point.row, start - 1))) : (start -= 1) {}
        while (end + 1 < frame.cols and isWordCell(frame.cell(point.row, end + 1))) : (end += 1) {}
        self.selection_anchor = .{ .row = point.row, .col = start };
        self.selection_head = .{ .row = point.row, .col = end };
    }

    fn selectRowAt(self: *WindowsRuntime, point: SelectionPoint) void {
        const frame = self.activeFrame();
        if (point.row >= frame.rows or frame.cols == 0) return;
        self.selection_anchor = .{ .row = point.row, .col = 0 };
        self.selection_head = .{ .row = point.row, .col = frame.cols - 1 };
    }

    fn clearSelection(self: *WindowsRuntime) void {
        self.selection_anchor = null;
        self.selection_head = null;
    }

    fn handleCopyModeKey(self: *WindowsRuntime, vkey: u32, mods: platform.KeyModifiers) !bool {
        _ = mods;
        const frame = self.activeFrame();
        switch (vkey) {
            win32.VK_ESCAPE, 'Q' => {
                self.copy_mode.exit();
                self.requestRepaint();
                return true;
            },
            'V' => {
                self.copy_mode.toggleVisual();
                self.requestRepaint();
                return true;
            },
            'B' => {
                self.copy_mode.toggleVisualLine();
                self.requestRepaint();
                return true;
            },
            'Y' => {
                if (self.copy_mode.selection(frame.cols)) |sel| {
                    self.selection_anchor = .{ .row = sel.start.row, .col = sel.start.col };
                    self.selection_head = .{ .row = sel.end.row, .col = sel.end.col };
                    try self.copySelectionToClipboard();
                }
                self.copy_mode.exit();
                self.requestRepaint();
                return true;
            },
            'H', win32.VK_LEFT => self.copy_mode.moveBy(0, -1, frame.rows, frame.cols),
            'J', win32.VK_DOWN => self.copy_mode.moveBy(1, 0, frame.rows, frame.cols),
            'K', win32.VK_UP => self.copy_mode.moveBy(-1, 0, frame.rows, frame.cols),
            'L', win32.VK_RIGHT => self.copy_mode.moveBy(0, 1, frame.rows, frame.cols),
            else => return false,
        }
        self.requestRepaint();
        return true;
    }

    fn copySelectionToClipboard(self: *WindowsRuntime) !void {
        const text = try self.selectionTextAlloc();
        defer self.allocator.free(text);
        if (text.len == 0) return;
        try self.window.copyTextToClipboard(text);
        try self.setStatusMessage("Copied selection");
    }

    fn pasteClipboard(self: *WindowsRuntime) !void {
        const text = self.window.readTextFromClipboard(self.allocator) catch return;
        defer self.allocator.free(text);
        const buf = try self.allocator.alloc(u8, text.len + 16);
        defer self.allocator.free(buf);
        const wrapped = try input_mod.wrapPaste(self.pane.engine.state.bracketed_paste, text, buf);
        self.clearSelection();
        try self.pane.sendInput(wrapped);
    }

    fn selectionTextAlloc(self: *WindowsRuntime) ![]u8 {
        if (self.selection_anchor == null or self.selection_head == null) {
            return try self.allocator.dupe(u8, "");
        }
        const a = self.selection_anchor.?;
        const b = self.selection_head.?;
        const start_row = @min(a.row, b.row);
        const end_row = @max(a.row, b.row);
        const start_col = @min(a.col, b.col);
        const end_col = @max(a.col, b.col);

        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);

        var row = start_row;
        const frame = self.activeFrame();
        while (row <= end_row and row < frame.rows) : (row += 1) {
            const row_start = if (row == start_row) start_col else 0;
            const row_end = if (row == end_row) end_col else frame.cols - 1;
            var col = row_start;
            while (col <= row_end and col < frame.cols) : (col += 1) {
                const cell = frame.cell(row, col);
                if (cell.wide_continuation) continue;
                var utf8_buf: [16]u8 = undefined;
                const cp = if (cell.char == 0) ' ' else cell.char;
                const len = std.unicode.utf8Encode(cp, &utf8_buf) catch 0;
                if (len != 0) try out.appendSlice(self.allocator, utf8_buf[0..len]);
                for (cell.combining) |comb| {
                    if (comb == 0) break;
                    const clen = std.unicode.utf8Encode(comb, &utf8_buf) catch 0;
                    if (clen != 0) try out.appendSlice(self.allocator, utf8_buf[0..clen]);
                }
            }
            if (row < end_row) try out.append(self.allocator, '\n');
        }
        return try out.toOwnedSlice(self.allocator);
    }

    fn mouseColFromClient(self: *const WindowsRuntime, client_x: i32) u16 {
        const inner_x = client_x - self.config.padding_px;
        const col = @divFloor(@max(0, inner_x), @max(1, self.config.cell_width_px)) + 1;
        return @intCast(@min(@as(i32, @intCast(self.pane.engine.state.colCount())), @max(1, col)));
    }

    fn mouseRowFromClient(self: *const WindowsRuntime, client_y: i32) u16 {
        const inner_y = client_y - self.config.padding_px;
        const row = @divFloor(@max(0, inner_y), @max(1, self.config.cell_height_px)) + 1;
        return @intCast(@min(@as(i32, @intCast(self.pane.engine.state.rowCount())), @max(1, row)));
    }

    fn waitForInitialShellPaint(self: *WindowsRuntime) !void {
        var attempts: usize = 0;
        while (attempts < 20) : (attempts += 1) {
            self.mutex.lock();
            _ = try self.pane.pollOnce();
            try self.refreshPublishedFrameLocked(true);
            self.mutex.unlock();
            if (frameHasVisibleContent(self.activeFrame())) return;

            std.Thread.sleep(50 * std.time.ns_per_ms);
        }
    }

    fn frameHasVisibleContent(frame: *const publish_mod.Frame) bool {
        for (frame.cells) |cell| {
            if (cell.wide_continuation) continue;
            if (cell.char != ' ') return true;
        }
        return false;
    }

    fn applyMeasuredFontMetrics(self: *WindowsRuntime) void {
        const font_metrics = self.window.fontMetrics();
        self.config.cell_width_px = font_metrics.cell_width_px;
        self.config.cell_height_px = font_metrics.cell_height_px;
        self.config.paint_metrics.cell_width_px = font_metrics.cell_width_px;
        self.config.paint_metrics.cell_height_px = font_metrics.cell_height_px;
        self.config.paint_metrics.cursor_width_px = font_metrics.cell_width_px;
        self.config.paint_metrics.cursor_bar_width_px = @max(2, @divFloor(font_metrics.cell_width_px, 6));
        self.config.paint_metrics.cursor_height_px = @max(2, @divFloor(font_metrics.cell_height_px, 7));
        self.config.paint_metrics.underline_height_px = @max(2, @divFloor(font_metrics.cell_height_px, 10));
    }

    fn syncWindowTitle(self: *WindowsRuntime) !void {
        const shell_title = self.pane.engine.state.title orelse {
            try self.setTitleCached(self.config.title);
            return;
        };
        if (shell_title.len == 0) {
            try self.setTitleCached(self.config.title);
            return;
        }
        try self.setTitleCached(shell_title);
        self.debugLog("title={s}", .{shell_title});
    }

    fn setTitleCached(self: *WindowsRuntime, text: []const u8) !void {
        if (std.mem.eql(u8, self.last_title.items, text)) return;
        try self.last_title.resize(self.allocator, text.len);
        @memcpy(self.last_title.items, text);
        try self.window.setTitle(text);
    }

    fn setFooterCached(self: *WindowsRuntime, text: []const u8) !void {
        if (std.mem.eql(u8, self.last_footer.items, text)) return;
        try self.last_footer.resize(self.allocator, text.len);
        @memcpy(self.last_footer.items, text);
        try self.window.setFooterText(text);
    }

    fn setStatusMessage(self: *WindowsRuntime, text: []const u8) !void {
        try self.status_message.resize(self.allocator, text.len);
        @memcpy(self.status_message.items, text);
        self.status_until_ms = std.time.milliTimestamp() + 2200;
        try self.setFooterCached(text);
        self.requestRepaint();
    }

    fn setStatusMessageFmt(self: *WindowsRuntime, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.setStatusMessage(text);
    }

    fn handleOverlayKey(self: *WindowsRuntime, vkey: u32, mods: platform.KeyModifiers) !bool {
        _ = mods;
        switch (vkey) {
            win32.VK_ESCAPE => {
                self.overlay.close();
                self.requestRepaint();
                return true;
            },
            win32.VK_UP => {
                self.overlay.movePrev();
                self.requestRepaint();
                return true;
            },
            win32.VK_DOWN, win32.VK_TAB => {
                self.overlay.moveNext();
                self.requestRepaint();
                return true;
            },
            win32.VK_RETURN => {
                try self.activateOverlayAction();
                return true;
            },
            else => return false,
        }
    }

    fn activateOverlayAction(self: *WindowsRuntime) !void {
        const action = self.overlay.currentAction() orelse return;
        switch (action) {
            .screenshot => {
                const path = try self.screenshotPathAlloc();
                defer self.allocator.free(path);
                try self.window.saveClientScreenshotPng(path);
                try self.setStatusMessageFmt("Saved {s}", .{std.fs.path.basename(path)});
                self.overlay.close();
            },
            .toggle_fullscreen => {
                try self.window.toggleFullscreen();
                try self.reflowToCurrentClientSize();
                try self.refreshWindowStateLocked(true);
                self.overlay.close();
            },
            .toggle_zen => {
                try self.window.toggleZen();
                try self.reflowToCurrentClientSize();
                try self.refreshWindowStateLocked(true);
                self.overlay.close();
            },
            .enter_copy_mode => {
                self.copy_mode.enter(self.pane.engine.state.cursor.row, self.pane.engine.state.cursor.col);
                self.overlay.close();
                try self.setStatusMessage("Copy mode");
            },
            .open_theme_picker => {
                self.overlay.open(.theme_picker);
            },
            .theme_default => {
                try self.applyTheme(.default);
                self.overlay.close();
            },
            .theme_mac_bw => {
                try self.applyTheme(.mac_bw);
                self.overlay.close();
            },
            .theme_amber => {
                try self.applyTheme(.amber);
                self.overlay.close();
            },
            .copy => {
                try self.copySelectionToClipboard();
                self.overlay.close();
            },
            .paste => {
                try self.pasteClipboard();
                self.overlay.close();
            },
        }
        self.requestRepaint();
    }

    fn applyTheme(self: *WindowsRuntime, preset: paint_mod.ThemePreset) !void {
        self.config.paint_theme = paint_mod.themePreset(preset);
        self.config.window_style = paint_mod.windowStylePreset(preset);
        try self.window.applyStyle(self.config.window_style);
        self.pane.engine.state.theme_colors = .{
            .fg = colorFromColorref(self.config.paint_theme.foreground_rgb),
            .bg = colorFromColorref(self.config.paint_theme.background_rgb),
            .cursor = colorFromColorref(self.config.paint_theme.cursor_rgb),
        };
        try self.setStatusMessageFmt("Theme: {s}", .{@tagName(preset)});
        try self.refreshPublishedFrameLocked(true);
    }

    fn debugLog(self: *WindowsRuntime, comptime fmt: []const u8, args: anytype) void {
        const file = self.debug_log_file orelse return;
        var buf: [1024]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, fmt, args) catch return;
        file.writeAll(line) catch return;
        file.writeAll("\n") catch return;
    }

    fn injectWindowInput(self: *WindowsRuntime, bytes: []const u8) !void {
        for (bytes) |byte| {
            switch (byte) {
                '\r' => try onKeyDown(@ptrCast(self), 0x0D, .{}, false),
                '\t' => try onKeyDown(@ptrCast(self), 0x09, .{}, false),
                0x08 => try onKeyDown(@ptrCast(self), 0x08, .{}, false),
                0x1b => try onKeyDown(@ptrCast(self), 0x1B, .{}, false),
                else => try onChar(@ptrCast(self), byte, .{}),
            }
        }
    }

    fn ensurePollThread(self: *WindowsRuntime) !void {
        if (self.poll_thread != null) return;
        self.stop_poll.store(false, .seq_cst);
        self.poll_thread = try std.Thread.spawn(.{}, pollThreadMain, .{self});
    }

    fn pollThreadMain(self: *WindowsRuntime) void {
        while (!self.stop_poll.load(.seq_cst)) {
            var needs_repaint = false;
            self.mutex.lock();
            const read = self.pane.pollOnce() catch 0;
            const exited = self.pane.childExited();
            if (read > 0 or exited) {
                self.cursor_blink_on = true;
                self.pane.engine.state.cursor.visible = true;
                self.refreshPublishedFrameLocked(false) catch {};
                needs_repaint = true;
                if (exited) self.child_exit_seen.store(true, .seq_cst);
            }
            self.mutex.unlock();

            if (needs_repaint) self.requestRepaint();
            std.Thread.sleep(5 * std.time.ns_per_ms);
        }
    }

    fn activeFrame(self: *const WindowsRuntime) *const publish_mod.Frame {
        return &self.frames[self.active_frame.load(.acquire)];
    }

    fn requestRepaint(self: *WindowsRuntime) void {
        if (!self.repaint_pending.swap(true, .acq_rel)) {
            self.window.requestRepaint();
        }
    }

    fn screenshotPathAlloc(self: *WindowsRuntime) ![]u8 {
        const dir = if (self.pane.engine.state.cwd) |cwd|
            try self.allocator.dupe(u8, cwd)
        else
            try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(dir);

        const filename = try std.fmt.allocPrint(self.allocator, "fmus-terminal-{d}.png", .{std.time.milliTimestamp()});
        defer self.allocator.free(filename);
        return try std.fs.path.join(self.allocator, &.{ dir, filename });
    }

};

fn colorFromColorref(rgb: u32) ThemeRgb {
    return .{
        .r = @truncate(rgb & 0xff),
        .g = @truncate((rgb >> 8) & 0xff),
        .b = @truncate((rgb >> 16) & 0xff),
    };
}

fn isWordCell(cell: cell_mod.Cell) bool {
    if (cell.wide_continuation) return false;
    const cp = cell.char;
    return (cp >= 'a' and cp <= 'z') or
        (cp >= 'A' and cp <= 'Z') or
        (cp >= '0' and cp <= '9') or
        cp == '_' or
        cp == '-' or
        cp == '.' or
        cp == '/' or
        cp == '\\';
}

test "runtime module compiles" {
    try std.testing.expect(@sizeOf(Config) > 0);
}
