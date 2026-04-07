const std = @import("std");
const action_mod = @import("action.zig");
const cell_mod = @import("cell.zig");
const color_mod = @import("color.zig");
const grid_mod = @import("grid.zig");
const dirty_mod = @import("dirty.zig");
const ring_mod = @import("ring.zig");
const ring_reflow = @import("ring_reflow.zig");
const style_mod = @import("style.zig");
const unicode = @import("unicode.zig");
const debug_mod = @import("debug.zig");

pub const Cursor = struct {
    row: usize = 0,
    col: usize = 0,
    visible: bool = true,
};

const SavedState = struct {
    cursor: Cursor = .{},
    scroll_top: usize = 0,
    scroll_bottom: usize = 0,
};

pub const ThemeColors = struct {
    fg: color_mod.Rgb = .{ .r = 220, .g = 220, .b = 220 },
    bg: color_mod.Rgb = .{ .r = 30, .g = 30, .b = 36 },
    cursor: ?color_mod.Rgb = null,
    palette: [16]?color_mod.Rgb = .{null} ** 16,
};

pub const State = struct {
    allocator: std.mem.Allocator,
    grid: grid_mod.Grid,
    alt_grid: grid_mod.Grid,
    ring: ring_mod.RingBuffer,
    scrollback_limit: usize = 2000,
    viewport_offset: usize = 0,
    title: ?[]u8 = null,
    cwd: ?[]u8 = null,
    using_alt_screen: bool = false,
    auto_wrap: bool = true,
    wrap_next: bool = false,
    cursor_keys_app: bool = false,
    keypad_app_mode: bool = false,
    synchronized_output: bool = false,
    bracketed_paste: bool = false,
    mouse_tracking: action_mod.MouseTrackingMode = .off,
    mouse_sgr: bool = false,
    kitty_kbd_flags: [16]u5 = .{0} ** 16,
    kitty_kbd_stack_len: u4 = 0,
    response_buf: [512]u8 = undefined,
    response_len: usize = 0,
    theme_colors: ThemeColors = .{},
    cursor: Cursor = .{},
    saved_cursor: SavedState = .{},
    scroll_top: usize = 0,
    scroll_bottom: usize = 0,
    cursor_shape: action_mod.CursorShape = .block,
    style: style_mod.Style = .{},
    dirty: dirty_mod.DirtyRows = .{},
    force_full_publish: bool = true,

    pub fn init(allocator: std.mem.Allocator, row_count: usize, col_count: usize) !State {
        var grid = try grid_mod.Grid.init(allocator, row_count, col_count);
        errdefer grid.deinit();
        var alt_grid = try grid_mod.Grid.init(allocator, row_count, col_count);
        errdefer alt_grid.deinit();
        var ring = try ring_mod.RingBuffer.init(allocator, row_count, col_count, 2000);
        errdefer ring.deinit();
        return .{
            .allocator = allocator,
            .grid = grid,
            .alt_grid = alt_grid,
            .ring = ring,
            .scroll_bottom = row_count - 1,
        };
    }

    pub fn deinit(self: *State) void {
        self.ring.deinit();
        if (self.title) |title| self.allocator.free(title);
        if (self.cwd) |cwd| self.allocator.free(cwd);
        self.alt_grid.deinit();
        self.grid.deinit();
    }

    pub fn apply(self: *State, action: action_mod.Action) void {
        debug_mod.log("state.apply tag={s} cursor=({d},{d})", .{ @tagName(action), self.cursor.row, self.cursor.col });
        switch (action) {
            .print,
            .nop,
            .sgr,
            .set_title,
            .set_cwd,
            .query_dec_private_mode,
            .query_color,
            .query_palette_color,
            .primary_device_attributes,
            .secondary_device_attributes,
            .device_status_report,
            .set_cursor_shape,
            .kitty_push_flags,
            .kitty_pop_flags,
            .kitty_query_flags,
            .set_keypad_app_mode,
            .reset_keypad_app_mode,
            .cursor_visible,
            .auto_wrap,
            .bracketed_paste,
            .mouse_tracking,
            .mouse_sgr,
            .set_alt_screen,
            => {},
            else => self.wrap_next = false,
        }
        switch (action) {
            .nop => {},
            .print => |char| self.putChar(char),
            .carriage_return => self.cursor.col = 0,
            .line_feed => self.lineFeed(),
            .form_feed => self.formFeed(),
            .backspace => {
                if (self.cursor.col > 0) {
                    self.cursor.col -= 1;
                    while (self.cursor.col > 0 and self.activeGrid().getConst(self.cursor.row, self.cursor.col).wide_continuation) {
                        self.cursor.col -= 1;
                    }
                }
            },
            .tab => {
                const next = ((self.cursor.col / 4) + 1) * 4;
                self.cursor.col = if (next >= self.activeGrid().cols) self.activeGrid().cols - 1 else next;
            },
            .set_title => |title| self.setTitle(title),
            .set_cwd => |cwd| self.setCwd(cwd),
            .set_alt_screen => |enabled| self.setAltScreen(enabled),
            .auto_wrap => |enabled| {
                self.auto_wrap = enabled;
                if (!enabled) self.wrap_next = false;
            },
            .bracketed_paste => |enabled| self.bracketed_paste = enabled,
            .mouse_tracking => |mode| self.mouse_tracking = mode,
            .mouse_sgr => |enabled| self.mouse_sgr = enabled,
            .kitty_push_flags => |flags| self.kittyPushFlags(flags),
            .kitty_pop_flags => |count| self.kittyPopFlags(count),
            .kitty_query_flags => self.respondKittyFlags(),
            .query_dec_private_mode => |mode| self.respondDecRequestMode(mode),
            .query_color => |target| self.respondColorQuery(target),
            .query_palette_color => |index| self.respondPaletteColorQuery(index),
            .primary_device_attributes => self.respondDeviceAttributes(),
            .secondary_device_attributes => self.respondSecondaryDeviceAttributes(),
            .device_status_report => |value| if (value == 5) self.respondDeviceStatus() else if (value == 6) self.respondCursorPosition(),
            .set_keypad_app_mode => self.keypad_app_mode = true,
            .reset_keypad_app_mode => self.keypad_app_mode = false,
            .save_cursor => self.saved_cursor = .{
                .cursor = self.cursor,
                .scroll_top = self.scroll_top,
                .scroll_bottom = self.scroll_bottom,
            },
            .restore_cursor => {
                self.cursor = .{
                    .row = @min(self.saved_cursor.cursor.row, self.activeGrid().rows - 1),
                    .col = @min(self.saved_cursor.cursor.col, self.activeGrid().cols - 1),
                    .visible = self.saved_cursor.cursor.visible,
                };
                self.scroll_top = @min(self.saved_cursor.scroll_top, self.activeGrid().rows - 1);
                self.scroll_bottom = @min(self.saved_cursor.scroll_bottom, self.activeGrid().rows - 1);
                if (self.scroll_top >= self.scroll_bottom) {
                    self.scroll_top = 0;
                    self.scroll_bottom = self.activeGrid().rows - 1;
                }
            },
            .reverse_index => self.reverseIndex(),
            .cursor_visible => |visible| self.cursor.visible = visible,
            .cursor_up => |amount| self.cursor.row -|= amount,
            .cursor_down => |amount| {
                self.cursor.row = @min(self.cursor.row + amount, self.activeGrid().rows - 1);
            },
            .cursor_forward => |amount| {
                self.cursor.col = @min(self.cursor.col + amount, self.activeGrid().cols - 1);
            },
            .cursor_backward => |amount| self.cursor.col -|= amount,
            .cursor_horizontal_absolute => |col| {
                self.cursor.col = @min(col, self.activeGrid().cols - 1);
            },
            .cursor_vertical_absolute => |row| {
                self.cursor.row = @min(row, self.activeGrid().rows - 1);
            },
            .cursor_position => |position| {
                self.cursor.row = @min(position.row, self.activeGrid().rows - 1);
                self.cursor.col = @min(position.col, self.activeGrid().cols - 1);
            },
            .set_scroll_region => |region| self.setScrollRegion(region),
            .insert_lines => |count| self.insertLines(count),
            .delete_lines => |count| self.deleteLines(count),
            .insert_chars => |count| self.insertChars(count),
            .delete_chars => |count| self.deleteChars(count),
            .scroll_up => |count| self.scrollUp(count),
            .scroll_down => |count| self.scrollDown(count),
            .erase_in_display => |mode| self.eraseInDisplay(mode),
            .erase_in_line => |mode| self.eraseInLine(mode),
            .erase_chars => |count| self.eraseChars(count),
            .set_cursor_shape => |shape| self.cursor_shape = shape,
            .sgr => |sgr| self.applySgr(sgr),
        }

        if (!self.using_alt_screen) self.syncMainGridToRing();
    }

    fn putChar(self: *State, char: u21) void {
        const grid = self.activeGrid();
        if (self.cursor.row >= grid.rows or self.cursor.col >= grid.cols) return;

        if (unicode.isZeroWidth(char) or unicode.isCombiningMark(char)) {
            self.applyZeroWidth(char);
            return;
        }

        if (self.wrap_next) {
            if (self.auto_wrap) {
                if (!self.using_alt_screen) {
                    self.ring.setScreenWrapped(self.cursor.row, true);
                }
                self.cursor.col = 0;
                self.cursorDown();
            }
            self.wrap_next = false;
        }

        const width = unicode.charDisplayWidth(char);
        self.clearCellFootprint(self.cursor.row, self.cursor.col);
        grid.get(self.cursor.row, self.cursor.col).* = .{
            .char = char,
            .combining = .{ 0, 0 },
            .wide_continuation = false,
            .style = self.style,
        };
        if (width == 2 and self.cursor.col + 1 < grid.cols) {
            grid.get(self.cursor.row, self.cursor.col + 1).* = .{
                .char = ' ',
                .combining = .{ 0, 0 },
                .wide_continuation = true,
                .style = self.style,
            };
        }
        self.dirty.mark(self.cursor.row);
        if (!self.using_alt_screen) self.syncMainGridToRing();
        self.advanceCursor(width);
    }

    fn advanceCursor(self: *State, width: usize) void {
        const grid = self.activeGrid();
        if (self.cursor.col + width < grid.cols) {
            self.cursor.col += width;
            return;
        }
        self.wrap_next = self.auto_wrap;
    }

    fn lineFeed(self: *State) void {
        self.viewport_offset = 0;
        self.cursorDown();
    }

    fn formFeed(self: *State) void {
        self.cursor.row = 0;
        self.cursor.col = 0;
        self.eraseInDisplay(2);
        self.force_full_publish = true;
    }

    fn eraseInDisplay(self: *State, mode: usize) void {
        const blank = self.bceCell();
        const grid = self.activeGrid();
        switch (mode) {
            2 => self.clearGridWithBlank(grid, blank),
            1 => {
                var row: usize = 0;
                while (row < self.cursor.row) : (row += 1) self.fillRow(row, 0, grid.cols, blank);
                self.fillRow(self.cursor.row, 0, @min(self.cursor.col + 1, grid.cols), blank);
            },
            else => {
                self.fillRow(self.cursor.row, self.cursor.col, grid.cols, blank);
                var row = self.cursor.row + 1;
                while (row < grid.rows) : (row += 1) self.fillRow(row, 0, grid.cols, blank);
            },
        }
        if (!self.using_alt_screen) self.syncMainGridToRing();
        self.dirty.markAll(grid.rows);
        self.force_full_publish = true;
    }

    fn eraseInLine(self: *State, mode: usize) void {
        const blank = self.bceCell();
        const grid = self.activeGrid();
        switch (mode) {
            2 => self.fillRow(self.cursor.row, 0, grid.cols, blank),
            1 => self.fillRow(self.cursor.row, 0, @min(self.cursor.col + 1, grid.cols), blank),
            else => self.fillRow(self.cursor.row, self.cursor.col, grid.cols, blank),
        }
        if (!self.using_alt_screen) self.syncMainGridToRing();
        self.dirty.mark(self.cursor.row);
    }

    fn eraseChars(self: *State, count: usize) void {
        if (!self.using_alt_screen) {
            self.ring.eraseChars(self.cursor.row, self.cursor.col, @max(@as(usize, 1), count), self.bceCell());
            self.syncMainScreenFromRing();
        } else {
            const grid = self.activeGrid();
            const stop = @min(grid.cols, self.cursor.col + @max(@as(usize, 1), count));
            var col = self.cursor.col;
            while (col < stop) : (col += 1) {
                if (grid.getConst(self.cursor.row, col).wide_continuation and col > 0) {
                    grid.get(self.cursor.row, col - 1).* = self.bceCell();
                }
                grid.get(self.cursor.row, col).* = self.bceCell();
            }
        }
        self.dirty.mark(self.cursor.row);
    }

    fn insertLines(self: *State, count: usize) void {
        const n = @max(@as(usize, 1), count);
        if (!self.using_alt_screen) {
            self.ring.scrollDownRegionN(self.cursor.row, self.grid.rows - 1, n, self.bceCell());
            self.syncMainScreenFromRing();
            self.dirty.markRange(self.cursor.row, self.grid.rows - 1);
        } else {
            const grid = self.activeGrid();
            grid.scrollDownRegion(self.cursor.row, grid.rows - 1, n);
            self.dirty.markRange(self.cursor.row, grid.rows - 1);
        }
    }

    fn deleteLines(self: *State, count: usize) void {
        const n = @max(@as(usize, 1), count);
        if (!self.using_alt_screen) {
            self.ring.scrollUpRegionN(self.cursor.row, self.grid.rows - 1, n, self.bceCell());
            self.syncMainScreenFromRing();
            self.dirty.markRange(self.cursor.row, self.grid.rows - 1);
        } else {
            const grid = self.activeGrid();
            grid.scrollUpRegion(self.cursor.row, grid.rows - 1, n);
            self.dirty.markRange(self.cursor.row, grid.rows - 1);
        }
    }

    fn insertChars(self: *State, count: usize) void {
        const n = @max(@as(usize, 1), count);
        if (!self.using_alt_screen) {
            self.ring.insertChars(self.cursor.row, self.cursor.col, n, self.bceCell());
            self.syncMainScreenFromRing();
        } else {
            self.insertCharsAlt(n, self.bceCell());
        }
        self.dirty.mark(self.cursor.row);
    }

    fn deleteChars(self: *State, count: usize) void {
        const n = @max(@as(usize, 1), count);
        if (!self.using_alt_screen) {
            self.ring.deleteChars(self.cursor.row, self.cursor.col, n, self.bceCell());
            self.syncMainScreenFromRing();
        } else {
            self.deleteCharsAlt(n, self.bceCell());
        }
        self.dirty.mark(self.cursor.row);
    }

    fn scrollUp(self: *State, count: usize) void {
        const n = @max(@as(usize, 1), count);
        if (!self.using_alt_screen) {
            self.ring.scrollUpRegionN(0, self.grid.rows - 1, n, self.bceCell());
            self.syncMainScreenFromRing();
            self.dirty.markAll(self.grid.rows);
        } else {
            const grid = self.activeGrid();
            grid.scrollUpRegion(0, grid.rows - 1, n);
            self.dirty.markAll(grid.rows);
        }
    }

    fn scrollDown(self: *State, count: usize) void {
        const n = @max(@as(usize, 1), count);
        if (!self.using_alt_screen) {
            self.ring.scrollDownRegionN(0, self.grid.rows - 1, n, self.bceCell());
            self.syncMainScreenFromRing();
            self.dirty.markAll(self.grid.rows);
        } else {
            const grid = self.activeGrid();
            grid.scrollDownRegion(0, grid.rows - 1, n);
            self.dirty.markAll(grid.rows);
        }
    }

    fn applyZeroWidth(self: *State, char: u21) void {
        const grid = self.activeGrid();
        if (self.cursor.col == 0) return;

        var base_col = self.cursor.col - 1;
        while (base_col > 0 and grid.getConst(self.cursor.row, base_col).wide_continuation) {
            base_col -= 1;
        }
        const base = grid.get(self.cursor.row, base_col);

        if (char == 0xFE0F and unicode.isTextDefaultEmoji(base.char) and self.cursor.col < grid.cols) {
            grid.get(self.cursor.row, self.cursor.col).* = .{
                .char = ' ',
                .combining = .{ 0, 0 },
                .wide_continuation = true,
                .style = self.style,
            };
            self.advanceCursor(1);
            return;
        }

        if (base.combining[0] == 0) {
            base.combining[0] = char;
        } else if (base.combining[1] == 0) {
            base.combining[1] = char;
        }
    }

    fn clearCellFootprint(self: *State, row: usize, col: usize) void {
        const grid = self.activeGrid();
        if (grid.getConst(row, col).wide_continuation and col > 0) {
            grid.get(row, col - 1).* = .{};
        }
        if (col + 1 < grid.cols and grid.getConst(row, col + 1).wide_continuation) {
            grid.get(row, col + 1).* = .{};
        }
        grid.get(row, col).* = .{};
    }

    fn applySgr(self: *State, sgr: action_mod.Sgr) void {
        switch (sgr) {
            .reset => self.style.reset(),
            .bold_on => self.style.bold = true,
            .bold_off => self.style.bold = false,
            .dim_on => self.style.dim = true,
            .dim_off => self.style.dim = false,
            .italic_on => self.style.italic = true,
            .italic_off => self.style.italic = false,
            .underline_on => self.style.underline = true,
            .underline_off => self.style.underline = false,
            .reverse_on => self.style.reverse = true,
            .reverse_off => self.style.reverse = false,
            .strikethrough_on => self.style.strikethrough = true,
            .strikethrough_off => self.style.strikethrough = false,
            .fg => |value| self.style.fg = value,
            .bg => |value| self.style.bg = value,
        }
    }

    pub fn setCursor(self: *State, row: usize, col: usize) void {
        const grid = self.activeGrid();
        self.cursor.row = @min(row, grid.rows - 1);
        self.cursor.col = @min(col, grid.cols - 1);
    }

    pub fn resize(self: *State, row_count: usize, col_count: usize) !void {
        if (self.using_alt_screen) {
            try self.grid.resizeNoReflow(row_count, col_count);
            try self.alt_grid.resizeNoReflow(row_count, col_count);
            const new_ring = try ring_reflow.resizeNoReflow(&self.ring, row_count, col_count);
            self.ring.deinit();
            self.ring = new_ring;
        } else {
            const result = try ring_reflow.resize(&self.ring, row_count, col_count, self.cursor.row, self.cursor.col);
            self.ring.deinit();
            self.ring = result.ring;
            try self.grid.resizeNoReflow(row_count, col_count);
            try self.alt_grid.resizeNoReflow(row_count, col_count);
            var row: usize = 0;
            while (row < row_count) : (row += 1) {
                const src = self.ring.getScreenRow(row);
                const dst = self.grid.row(row);
                @memcpy(dst, src);
            }
            self.cursor.row = result.cursor_row;
            self.cursor.col = result.cursor_col;
        }

        self.cursor.row = @min(self.cursor.row, self.activeGridConst().rows - 1);
        self.cursor.col = @min(self.cursor.col, self.activeGridConst().cols - 1);
        self.scroll_top = @min(self.scroll_top, self.activeGridConst().rows - 1);
        self.scroll_bottom = self.activeGridConst().rows - 1;
        if (self.scroll_top >= self.scroll_bottom) self.scroll_top = 0;
        self.viewport_offset = 0;
        self.dirty.markAll(self.activeGridConst().rows);
        self.force_full_publish = true;
    }

    pub fn rowCount(self: *const State) usize {
        return self.activeGridConst().rows;
    }

    pub fn colCount(self: *const State) usize {
        return self.activeGridConst().cols;
    }

    pub fn totalRows(self: *const State) usize {
        if (self.using_alt_screen) return self.alt_grid.rows;
        return self.ring.scrollbackCount() + self.grid.rows;
    }

    pub fn cellAtView(self: *const State, row_index: usize, col_index: usize) cell_mod.Cell {
        if (self.using_alt_screen) {
            return self.alt_grid.getConst(row_index, col_index).*;
        }
        return self.ring.viewportRow(self.viewport_offset, row_index)[col_index];
    }

    pub fn rowWrappedAtView(self: *const State, row_index: usize) bool {
        if (self.using_alt_screen) return false;
        return self.ring.viewportRowWrapped(self.viewport_offset, row_index);
    }

    pub fn screenCellsDirect(self: *const State) ?[]const cell_mod.Cell {
        if (self.using_alt_screen) return null;
        if (self.viewport_offset != 0) return null;
        return self.ring.screenCellsDirect();
    }

    pub fn scrollViewportUp(self: *State, lines: usize) void {
        self.viewport_offset = @min(self.viewport_offset + lines, self.ring.scrollbackCount());
    }

    pub fn scrollViewportDown(self: *State, lines: usize) void {
        self.viewport_offset -|= lines;
    }

    pub fn scrollViewportToBottom(self: *State) void {
        self.viewport_offset = 0;
    }

    pub fn scrollbackCount(self: *const State) usize {
        return if (self.using_alt_screen) 0 else self.ring.scrollbackCount();
    }

    fn setTitle(self: *State, value: []const u8) void {
        if (self.title) |title| self.allocator.free(title);
        self.title = self.allocator.dupe(u8, value) catch null;
    }

    fn setCwd(self: *State, value: []const u8) void {
        if (self.cwd) |cwd| self.allocator.free(cwd);
        self.cwd = self.allocator.dupe(u8, value) catch null;
    }

    fn setAltScreen(self: *State, enabled: bool) void {
        if (enabled == self.using_alt_screen) return;
        if (enabled) {
            self.saved_cursor = .{
                .cursor = self.cursor,
                .scroll_top = self.scroll_top,
                .scroll_bottom = self.scroll_bottom,
            };
            self.using_alt_screen = true;
            self.viewport_offset = 0;
            self.alt_grid.clear();
            self.kittyResetFlags();
            self.cursor.row = 0;
            self.cursor.col = 0;
            self.cursor.visible = true;
            self.scroll_top = 0;
            self.scroll_bottom = self.alt_grid.rows - 1;
            self.dirty.markAll(self.alt_grid.rows);
            self.force_full_publish = true;
            return;
        }
        self.using_alt_screen = false;
        self.viewport_offset = 0;
        self.kittyResetFlags();
        self.cursor = .{
            .row = @min(self.saved_cursor.cursor.row, self.grid.rows - 1),
            .col = @min(self.saved_cursor.cursor.col, self.grid.cols - 1),
            .visible = self.saved_cursor.cursor.visible,
        };
        self.scroll_top = @min(self.saved_cursor.scroll_top, self.grid.rows - 1);
        self.scroll_bottom = @min(self.saved_cursor.scroll_bottom, self.grid.rows - 1);
        if (self.scroll_top >= self.scroll_bottom) {
            self.scroll_top = 0;
            self.scroll_bottom = self.grid.rows - 1;
        }
        self.dirty.markAll(self.grid.rows);
        self.force_full_publish = true;
    }

    pub fn kittyFlags(self: *const State) u5 {
        if (self.kitty_kbd_stack_len == 0) return 0;
        return self.kitty_kbd_flags[self.kitty_kbd_stack_len - 1];
    }

    fn kittyPushFlags(self: *State, flags: u5) void {
        if (self.kitty_kbd_stack_len < self.kitty_kbd_flags.len) {
            self.kitty_kbd_flags[self.kitty_kbd_stack_len] = flags;
            self.kitty_kbd_stack_len += 1;
            return;
        }
        var index: usize = 0;
        while (index + 1 < self.kitty_kbd_flags.len) : (index += 1) {
            self.kitty_kbd_flags[index] = self.kitty_kbd_flags[index + 1];
        }
        self.kitty_kbd_flags[self.kitty_kbd_flags.len - 1] = flags;
    }

    fn kittyPopFlags(self: *State, count: u8) void {
        const actual = @min(@as(usize, count), @as(usize, self.kitty_kbd_stack_len));
        self.kitty_kbd_stack_len -= @intCast(actual);
    }

    pub fn kittyResetFlags(self: *State) void {
        self.kitty_kbd_stack_len = 0;
    }

    pub fn drainResponse(self: *State) ?[]const u8 {
        if (self.response_len == 0) return null;
        const len = self.response_len;
        self.response_len = 0;
        return self.response_buf[0..len];
    }

    fn appendResponse(self: *State, data: []const u8) void {
        const avail = self.response_buf.len - self.response_len;
        const n = @min(avail, data.len);
        if (n == 0) return;
        @memcpy(self.response_buf[self.response_len .. self.response_len + n], data[0..n]);
        self.response_len += n;
    }

    fn respondDeviceStatus(self: *State) void {
        self.appendResponse("\x1b[0n");
    }

    fn respondCursorPosition(self: *State) void {
        var buf: [32]u8 = undefined;
        const resp = std.fmt.bufPrint(&buf, "\x1b[{d};{d}R", .{ self.cursor.row + 1, self.cursor.col + 1 }) catch return;
        self.appendResponse(resp);
    }

    fn respondDeviceAttributes(self: *State) void {
        self.appendResponse("\x1b[?62c");
    }

    fn respondSecondaryDeviceAttributes(self: *State) void {
        self.appendResponse("\x1b[>0;10;1c");
    }

    fn respondKittyFlags(self: *State) void {
        var buf: [32]u8 = undefined;
        const resp = std.fmt.bufPrint(&buf, "\x1b[?{d}u", .{self.kittyFlags()}) catch return;
        self.appendResponse(resp);
    }

    fn respondDecRequestMode(self: *State, mode: u16) void {
        const pm: u8 = switch (mode) {
            1 => if (self.cursor_keys_app) 1 else 2,
            2026 => if (self.synchronized_output) 1 else 2,
            else => 0,
        };
        var buf: [32]u8 = undefined;
        const resp = std.fmt.bufPrint(&buf, "\x1b[?{d};{d}$y", .{ mode, pm }) catch return;
        self.appendResponse(resp);
    }

    fn respondColorQuery(self: *State, target: action_mod.ColorQueryType) void {
        const rgb = switch (target) {
            .foreground => self.theme_colors.fg,
            .background => self.theme_colors.bg,
            .cursor => self.theme_colors.cursor orelse self.theme_colors.fg,
        };
        const osc_num: u8 = switch (target) {
            .foreground => 10,
            .background => 11,
            .cursor => 12,
        };
        var rb: [4]u8 = undefined;
        var gb: [4]u8 = undefined;
        var bb: [4]u8 = undefined;
        var buf: [64]u8 = undefined;
        const resp = std.fmt.bufPrint(&buf, "\x1b]{d};rgb:{s}/{s}/{s}\x07", .{
            osc_num,
            fmtColorComponent(&rb, rgb.r),
            fmtColorComponent(&gb, rgb.g),
            fmtColorComponent(&bb, rgb.b),
        }) catch return;
        self.appendResponse(resp);
    }

    fn respondPaletteColorQuery(self: *State, idx: u8) void {
        const rgb = resolvePaletteColor(self, idx);
        var rb: [4]u8 = undefined;
        var gb: [4]u8 = undefined;
        var bb: [4]u8 = undefined;
        var buf: [64]u8 = undefined;
        const resp = std.fmt.bufPrint(&buf, "\x1b]4;{d};rgb:{s}/{s}/{s}\x07", .{
            idx,
            fmtColorComponent(&rb, rgb.r),
            fmtColorComponent(&gb, rgb.g),
            fmtColorComponent(&bb, rgb.b),
        }) catch return;
        self.appendResponse(resp);
    }

    fn activeGrid(self: *State) *grid_mod.Grid {
        return if (self.using_alt_screen) &self.alt_grid else &self.grid;
    }

    fn activeGridConst(self: *const State) *const grid_mod.Grid {
        return if (self.using_alt_screen) &self.alt_grid else &self.grid;
    }

    fn syncMainGridToRing(self: *State) void {
        var row: usize = 0;
        while (row < self.grid.rows) : (row += 1) {
            const src = self.grid.rowConst(row);
            const dst = self.ring.getScreenRowMut(row);
            @memcpy(dst, src);
        }
    }

    fn syncMainScreenFromRing(self: *State) void {
        var row: usize = 0;
        while (row < self.grid.rows) : (row += 1) {
            const src = self.ring.getScreenRow(row);
            const dst = self.grid.row(row);
            @memcpy(dst, src);
        }
    }

    fn isFullScreenScroll(self: *const State) bool {
        return !self.using_alt_screen and self.scroll_top == 0 and self.scroll_bottom == self.grid.rows - 1;
    }

    fn isTopAnchoredMainScroll(self: *const State) bool {
        return !self.using_alt_screen and self.scroll_top == 0 and self.scroll_bottom < self.grid.rows - 1;
    }

    fn scrollUpActiveRegion(self: *State, count: usize) void {
        if (count == 0) return;
        if (self.isFullScreenScroll()) {
            for (0..count) |_| {
                _ = self.ring.advanceScreen();
                if (self.viewport_offset > 0) {
                    self.viewport_offset = @min(self.viewport_offset + 1, self.ring.scrollbackCount());
                }
            }
            self.syncMainScreenFromRing();
            return;
        }
        if (self.isTopAnchoredMainScroll()) {
            for (0..count) |_| {
                self.ring.scrollUpTopAnchoredRegionWithScrollback(self.scroll_bottom, self.bceCell());
                if (self.viewport_offset > 0) {
                    self.viewport_offset = @min(self.viewport_offset + 1, self.ring.scrollbackCount());
                }
            }
            self.syncMainScreenFromRing();
            return;
        }
        if (!self.using_alt_screen) {
            self.ring.scrollUpRegionN(self.scroll_top, self.scroll_bottom, count, self.bceCell());
            self.syncMainScreenFromRing();
            return;
        }
        self.alt_grid.scrollUpRegion(self.scroll_top, self.scroll_bottom, count);
    }

    fn reverseIndex(self: *State) void {
        if (self.cursor.row == self.scroll_top) {
            if (!self.using_alt_screen) {
                self.ring.scrollDownRegion(self.scroll_top, self.scroll_bottom, self.bceCell());
                self.syncMainScreenFromRing();
            } else {
                self.alt_grid.scrollDownRegion(self.scroll_top, self.scroll_bottom, 1);
            }
            self.dirty.markRange(self.scroll_top, self.scroll_bottom);
        } else if (self.cursor.row > 0) {
            self.cursor.row -= 1;
        }
    }

    fn cursorDown(self: *State) void {
        if (self.cursor.row == self.scroll_bottom) {
            self.scrollUpActiveRegion(1);
            self.dirty.markRange(self.scroll_top, self.scroll_bottom);
        } else if (self.cursor.row < self.activeGridConst().rows - 1) {
            self.cursor.row += 1;
        }
    }

    fn setScrollRegion(self: *State, region: action_mod.ScrollRegion) void {
        const rows = self.activeGridConst().rows;
        const top_1 = if (region.top == 0) 1 else @min(region.top, rows);
        const bottom_1 = if (region.bottom == 0) rows else @min(region.bottom, rows);
        const top = top_1 - 1;
        const bottom = bottom_1 - 1;
        if (top >= bottom) return;
        self.scroll_top = top;
        self.scroll_bottom = bottom;
        self.cursor.row = 0;
        self.cursor.col = 0;
    }

    fn bceCell(self: *const State) cell_mod.Cell {
        if (self.style.bg == .default) return .{};
        return .{ .style = .{ .bg = self.style.bg } };
    }

    fn clearGridWithBlank(self: *State, grid: *grid_mod.Grid, blank: cell_mod.Cell) void {
        var row: usize = 0;
        while (row < grid.rows) : (row += 1) self.fillRow(row, 0, grid.cols, blank);
    }

    fn fillRow(self: *State, row: usize, start: usize, end: usize, blank: cell_mod.Cell) void {
        const grid = self.activeGrid();
        var col = start;
        while (col < end) : (col += 1) grid.get(row, col).* = blank;
    }

    fn insertCharsAlt(self: *State, count: usize, blank: cell_mod.Cell) void {
        const grid = self.activeGrid();
        if (self.cursor.col >= grid.cols) return;
        const row_cells = grid.row(self.cursor.row);
        const n = @min(count, grid.cols - self.cursor.col);
        if (n == 0) return;
        var col: usize = grid.cols;
        while (col > self.cursor.col + n) {
            col -= 1;
            row_cells[col] = row_cells[col - n];
        }
        col = self.cursor.col;
        while (col < self.cursor.col + n) : (col += 1) row_cells[col] = blank;
    }

    fn deleteCharsAlt(self: *State, count: usize, blank: cell_mod.Cell) void {
        const grid = self.activeGrid();
        if (self.cursor.col >= grid.cols) return;
        const row_cells = grid.row(self.cursor.row);
        const n = @min(count, grid.cols - self.cursor.col);
        if (n == 0) return;
        var col = self.cursor.col;
        while (col + n < grid.cols) : (col += 1) row_cells[col] = row_cells[col + n];
        while (col < grid.cols) : (col += 1) row_cells[col] = blank;
    }
};

fn fmtColorComponent(buf: *[4]u8, val: u8) []const u8 {
    return std.fmt.bufPrint(buf, "{x:0>2}{x:0>2}", .{ val, val }) catch buf;
}

fn resolvePaletteColor(self: *const State, idx: u8) color_mod.Rgb {
    if (idx < 16) {
        if (self.theme_colors.palette[idx]) |p| return p;
    }
    return resolve256(idx);
}

fn cubeComponent(idx: u8) u8 {
    if (idx == 0) return 0;
    return @intCast(@as(u16, 55) + @as(u16, idx) * 40);
}

fn resolve256(n: u8) color_mod.Rgb {
    if (n < 16) return ansi16[n];
    if (n < 232) {
        const i = n - 16;
        return .{
            .r = cubeComponent(i / 36),
            .g = cubeComponent((i / 6) % 6),
            .b = cubeComponent(i % 6),
        };
    }
    const g: u8 = @intCast(@as(u16, 8) + @as(u16, n - 232) * 10);
    return .{ .r = g, .g = g, .b = g };
}

const ansi16 = [16]color_mod.Rgb{
    .{ .r = 0, .g = 0, .b = 0 },
    .{ .r = 170, .g = 0, .b = 0 },
    .{ .r = 0, .g = 170, .b = 0 },
    .{ .r = 170, .g = 85, .b = 0 },
    .{ .r = 0, .g = 0, .b = 170 },
    .{ .r = 170, .g = 0, .b = 170 },
    .{ .r = 0, .g = 170, .b = 170 },
    .{ .r = 170, .g = 170, .b = 170 },
    .{ .r = 85, .g = 85, .b = 85 },
    .{ .r = 255, .g = 85, .b = 85 },
    .{ .r = 85, .g = 255, .b = 85 },
    .{ .r = 255, .g = 255, .b = 85 },
    .{ .r = 85, .g = 85, .b = 255 },
    .{ .r = 255, .g = 85, .b = 255 },
    .{ .r = 85, .g = 255, .b = 255 },
    .{ .r = 255, .g = 255, .b = 255 },
};

pub fn ansiNamed(index: usize, bright: bool) color_mod.Color {
    const base: color_mod.Named = switch (index) {
        0 => if (bright) .bright_black else .black,
        1 => if (bright) .bright_red else .red,
        2 => if (bright) .bright_green else .green,
        3 => if (bright) .bright_yellow else .yellow,
        4 => if (bright) .bright_blue else .blue,
        5 => if (bright) .bright_magenta else .magenta,
        6 => if (bright) .bright_cyan else .cyan,
        else => if (bright) .bright_white else .white,
    };
    return .{ .named = base };
}

test "state prints and scrolls" {
    var state = try State.init(std.testing.allocator, 2, 3);
    defer state.deinit();

    for ("abcdefg") |byte| state.apply(.{ .print = byte });

    try std.testing.expectEqual(@as(u21, 'd'), state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'g'), state.grid.get(1, 0).char);
}

test "state resize preserves overlapping content" {
    var state = try State.init(std.testing.allocator, 2, 4);
    defer state.deinit();

    for ("abcd") |byte| state.apply(.{ .print = byte });
    try state.resize(3, 6);

    try std.testing.expectEqual(@as(u21, 'a'), state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'd'), state.grid.get(0, 3).char);
    try std.testing.expectEqual(@as(usize, 3), state.rowCount());
    try std.testing.expectEqual(@as(usize, 6), state.colCount());
}

test "state save restore cursor and erase modes" {
    var state = try State.init(std.testing.allocator, 3, 5);
    defer state.deinit();

    state.apply(.{ .print = 'a' });
    state.apply(.save_cursor);
    state.apply(.{ .cursor_position = .{ .row = 2, .col = 3 } });
    state.apply(.restore_cursor);
    try std.testing.expectEqual(@as(usize, 0), state.cursor.row);
    try std.testing.expectEqual(@as(usize, 1), state.cursor.col);

    state.apply(.{ .print = 'b' });
    state.apply(.{ .erase_in_line = 1 });
    try std.testing.expectEqual(@as(u21, ' '), state.grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), state.grid.get(0, 1).char);
}

test "state form feed clears screen and homes cursor" {
    var state = try State.init(std.testing.allocator, 3, 5);
    defer state.deinit();

    state.apply(.{ .print = 'a' });
    state.apply(.line_feed);
    state.apply(.{ .print = 'b' });
    state.apply(.form_feed);

    try std.testing.expectEqual(@as(usize, 0), state.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), state.cursor.col);
    try std.testing.expect(state.grid.get(0, 0).char == 0 or state.grid.get(0, 0).char == ' ');
    try std.testing.expect(state.grid.get(1, 0).char == 0 or state.grid.get(1, 0).char == ' ');
}

test "state stores title and cwd metadata" {
    var state = try State.init(std.testing.allocator, 2, 4);
    defer state.deinit();

    state.apply(.{ .set_title = "shell title" });
    state.apply(.{ .set_cwd = "C:\\work" });

    try std.testing.expectEqualStrings("shell title", state.title.?);
    try std.testing.expectEqualStrings("C:\\work", state.cwd.?);
}

test "state switches alternate screen" {
    var state = try State.init(std.testing.allocator, 2, 4);
    defer state.deinit();

    state.apply(.{ .print = 'a' });
    state.apply(.{ .set_alt_screen = true });
    state.apply(.{ .print = 'b' });
    try std.testing.expectEqual(@as(u21, 'b'), state.alt_grid.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'a'), state.grid.get(0, 0).char);

    state.apply(.{ .set_alt_screen = false });
    try std.testing.expectEqual(@as(u21, 'a'), state.grid.get(0, 0).char);
}

test "state stores wide characters across two cells" {
    var state = try State.init(std.testing.allocator, 2, 6);
    defer state.deinit();

    state.apply(.{ .print = 0x1F916 });

    try std.testing.expectEqual(@as(u21, 0x1F916), state.grid.get(0, 0).char);
    try std.testing.expect(state.grid.get(0, 1).wide_continuation);
    try std.testing.expectEqual(@as(usize, 2), state.cursor.col);
}

test "state upgrades text emoji with VS16" {
    var state = try State.init(std.testing.allocator, 2, 6);
    defer state.deinit();

    state.apply(.{ .print = 0x2733 });
    state.apply(.{ .print = 0xFE0F });

    try std.testing.expectEqual(@as(u21, 0x2733), state.grid.get(0, 0).char);
    try std.testing.expect(state.grid.get(0, 1).wide_continuation);
    try std.testing.expectEqual(@as(usize, 2), state.cursor.col);
}

test "state tracks kitty keyboard flags stack" {
    var state = try State.init(std.testing.allocator, 2, 4);
    defer state.deinit();

    try std.testing.expectEqual(@as(u5, 0), state.kittyFlags());
    state.apply(.{ .kitty_push_flags = 1 });
    try std.testing.expectEqual(@as(u5, 1), state.kittyFlags());
    state.apply(.{ .kitty_push_flags = 5 });
    try std.testing.expectEqual(@as(u5, 5), state.kittyFlags());
    state.apply(.{ .kitty_pop_flags = 1 });
    try std.testing.expectEqual(@as(u5, 1), state.kittyFlags());
}

test "state tracks bracketed paste and mouse modes" {
    var state = try State.init(std.testing.allocator, 2, 4);
    defer state.deinit();

    state.apply(.{ .bracketed_paste = true });
    state.apply(.{ .mouse_tracking = .any_event });
    state.apply(.{ .mouse_sgr = true });

    try std.testing.expect(state.bracketed_paste);
    try std.testing.expect(state.mouse_tracking == .any_event);
    try std.testing.expect(state.mouse_sgr);
}

test "state responds to dec request mode and color query" {
    var state = try State.init(std.testing.allocator, 2, 4);
    defer state.deinit();

    state.cursor_keys_app = true;
    state.apply(.{ .query_dec_private_mode = 1 });
    try std.testing.expectEqualStrings("\x1b[?1;1$y", state.drainResponse().?);

    state.apply(.{ .query_color = .foreground });
    try std.testing.expectEqualStrings("\x1b]10;rgb:dcdc/dcdc/dcdc\x07", state.drainResponse().?);
}
