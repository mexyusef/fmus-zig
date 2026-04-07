const std = @import("std");
const action_mod = @import("action.zig");
const state_mod = @import("state.zig");

const Mode = enum {
    ground,
    escape,
    csi,
    osc,
    osc_escape,
};

const Prefix = enum {
    none,
    private,
    greater,
    less,
};

pub const Parser = struct {
    mode: Mode = .ground,
    prefix: Prefix = .none,
    params_len: usize = 0,
    params: [8]?usize = [_]?usize{null} ** 8,
    csi_dollar: bool = false,
    pending_len: usize = 0,
    pending_index: usize = 0,
    pending: [16]action_mod.Action = undefined,
    osc_len: usize = 0,
    osc_overflow: bool = false,
    osc_buf: [1024]u8 = undefined,

    pub fn next(self: *Parser, byte: u8) ?action_mod.Action {
        if (self.pending_index < self.pending_len) {
            const action = self.pending[self.pending_index];
            self.pending_index += 1;
            if (self.pending_index == self.pending_len) {
                self.pending_index = 0;
                self.pending_len = 0;
            }
            return action;
        }
        return switch (self.mode) {
            .ground => self.consumeGround(byte),
            .escape => self.consumeEscape(byte),
            .csi => self.consumeCsi(byte),
            .osc => self.consumeOsc(byte),
            .osc_escape => self.consumeOscEscape(byte),
        };
    }

    pub fn isGround(self: *const Parser) bool {
        return self.mode == .ground and self.pending_index >= self.pending_len;
    }

    pub fn nextPending(self: *Parser) ?action_mod.Action {
        if (self.pending_index >= self.pending_len) return null;
        const action = self.pending[self.pending_index];
        self.pending_index += 1;
        if (self.pending_index == self.pending_len) {
            self.pending_index = 0;
            self.pending_len = 0;
        }
        return action;
    }

    fn consumeGround(self: *Parser, byte: u8) ?action_mod.Action {
        return switch (byte) {
            0x08 => .backspace,
            0x09 => .tab,
            0x0A => .line_feed,
            0x0C => .form_feed,
            0x0D => .carriage_return,
            0x1B => blk: {
                self.mode = .escape;
                break :blk null;
            },
            else => if (byte >= 0x20 and byte != 0x7F) .{ .print = byte } else null,
        };
    }

    fn consumeEscape(self: *Parser, byte: u8) ?action_mod.Action {
        self.mode = .ground;
        return switch (byte) {
            '7' => .save_cursor,
            '8' => .restore_cursor,
            'M' => .reverse_index,
            '[' => blk: {
                self.mode = .csi;
                self.resetParams();
                break :blk null;
            },
            '=' => .set_keypad_app_mode,
            '>' => .reset_keypad_app_mode,
            ']' => blk: {
                self.mode = .osc;
                self.osc_len = 0;
                self.osc_overflow = false;
                break :blk null;
            },
            else => null,
        };
    }

    fn consumeCsi(self: *Parser, byte: u8) ?action_mod.Action {
        if (byte == '?') {
            self.prefix = .private;
            return null;
        }
        if (byte == '>') {
            self.prefix = .greater;
            return null;
        }
        if (byte == '<') {
            self.prefix = .less;
            return null;
        }
        if (std.ascii.isDigit(byte)) {
            self.appendDigit(byte - '0');
            return null;
        }
        if (byte == ';') {
            self.pushParam();
            return null;
        }
        if (byte == '$') {
            self.csi_dollar = true;
            return null;
        }
        if (byte == ' ') {
            self.csi_dollar = true;
            return null;
        }
        if (byte >= 0x40 and byte <= 0x7E) {
            self.finalizeParamList();
            self.mode = .ground;
            const prefix = self.prefix;
            self.prefix = .none;
            return self.finalize(byte, prefix);
        }
        self.mode = .ground;
        self.prefix = .none;
        return null;
    }

    fn consumeOsc(self: *Parser, byte: u8) ?action_mod.Action {
        return switch (byte) {
            0x07 => blk: {
                self.mode = .ground;
                break :blk self.dispatchOsc();
            },
            0x1B => blk: {
                self.mode = .osc_escape;
                break :blk null;
            },
            else => blk: {
                if (!self.osc_overflow) {
                    if (self.osc_len < self.osc_buf.len) {
                        self.osc_buf[self.osc_len] = byte;
                        self.osc_len += 1;
                    } else {
                        self.osc_overflow = true;
                    }
                }
                break :blk null;
            },
        };
    }

    fn consumeOscEscape(self: *Parser, byte: u8) ?action_mod.Action {
        if (byte == '\\') {
            self.mode = .ground;
            return self.dispatchOsc();
        }
        self.mode = .escape;
        return self.consumeEscape(byte);
    }

    fn appendDigit(self: *Parser, digit: u8) void {
        const index = if (self.params_len == 0) blk: {
            self.params_len = 1;
            break :blk 0;
        } else self.params_len - 1;
        const current = self.params[index] orelse 0;
        self.params[index] = current * 10 + digit;
    }

    fn pushParam(self: *Parser) void {
        if (self.params_len == 0) {
            self.params_len = 1;
            return;
        }
        if (self.params_len < self.params.len and self.params[self.params_len - 1] != null) {
            self.params_len += 1;
        }
    }

    fn finalizeParamList(self: *Parser) void {
        if (self.params_len == 0) {
            self.params_len = 1;
        }
    }

    fn finalize(self: *Parser, final: u8, prefix: Prefix) ?action_mod.Action {
        const p1 = self.paramOr(0, 1);
        if (prefix == .private) {
            return switch (final) {
                'u' => .kitty_query_flags,
                'p' => if (self.csi_dollar) .{ .query_dec_private_mode = @intCast(self.paramOr(0, 0)) } else null,
                'h' => switch (self.paramOr(0, 0)) {
                    7 => .{ .auto_wrap = true },
                    25 => .{ .cursor_visible = true },
                    1049 => .{ .set_alt_screen = true },
                    1000 => .{ .mouse_tracking = .x10 },
                    1002 => .{ .mouse_tracking = .button_event },
                    1003 => .{ .mouse_tracking = .any_event },
                    1006 => .{ .mouse_sgr = true },
                    2004 => .{ .bracketed_paste = true },
                    else => null,
                },
                'l' => switch (self.paramOr(0, 0)) {
                    7 => .{ .auto_wrap = false },
                    25 => .{ .cursor_visible = false },
                    1049 => .{ .set_alt_screen = false },
                    1000, 1002, 1003 => .{ .mouse_tracking = .off },
                    1006 => .{ .mouse_sgr = false },
                    2004 => .{ .bracketed_paste = false },
                    else => null,
                },
                else => null,
            };
        }
        return switch (final) {
            'u' => switch (prefix) {
                .greater => .{ .kitty_push_flags = @intCast(@min(self.paramOr(0, 0), 31)) },
                .less => .{ .kitty_pop_flags = @intCast(@min(self.paramOr(0, 1), 255)) },
                else => .restore_cursor,
            },
            'c' => if (prefix == .greater) .secondary_device_attributes else .primary_device_attributes,
            'A' => .{ .cursor_up = p1 },
            'B' => .{ .cursor_down = p1 },
            'C' => .{ .cursor_forward = p1 },
            'D' => .{ .cursor_backward = p1 },
            'G' => .{ .cursor_horizontal_absolute = self.paramOr(0, 1) - 1 },
            'd' => .{ .cursor_vertical_absolute = self.paramOr(0, 1) - 1 },
            'n' => .{ .device_status_report = self.paramOr(0, 0) },
            's' => .save_cursor,
            '@' => .{ .insert_chars = self.paramOr(0, 1) },
            'L' => .{ .insert_lines = self.paramOr(0, 1) },
            'M' => .{ .delete_lines = self.paramOr(0, 1) },
            'P' => .{ .delete_chars = self.paramOr(0, 1) },
            'S' => .{ .scroll_up = self.paramOr(0, 1) },
            'T' => .{ .scroll_down = self.paramOr(0, 1) },
            'H', 'f' => .{
                .cursor_position = .{
                    .row = self.paramOr(0, 1) - 1,
                    .col = self.paramOr(1, 1) - 1,
                },
            },
            'r' => .{
                .set_scroll_region = .{
                    .top = self.paramOr(0, 1),
                    .bottom = self.paramOr(1, 0),
                },
            },
            'q' => if (self.csi_dollar) self.cursorShapeAction() else null,
            'J' => .{ .erase_in_display = self.paramOr(0, 0) },
            'K' => .{ .erase_in_line = self.paramOr(0, 0) },
            'X' => .{ .erase_chars = self.paramOr(0, 1) },
            'm' => self.sgrAction(),
            else => null,
        };
    }

    fn cursorShapeAction(self: *Parser) ?action_mod.Action {
        return .{ .set_cursor_shape = switch (self.paramOr(0, 0)) {
            3, 4 => .underline,
            5, 6 => .bar,
            else => .block,
        } };
    }

    fn sgrAction(self: *Parser) ?action_mod.Action {
        if (self.params_len == 0 or self.params[0] == null) {
            return .{ .sgr = .reset };
        }

        self.pending_len = 0;
        self.pending_index = 0;

        var index: usize = 0;
        while (index < self.params_len) {
            const code = self.paramOr(index, 0);
            switch (code) {
                0 => self.pushPending(.{ .sgr = .reset }),
                1 => self.pushPending(.{ .sgr = .bold_on }),
                2 => self.pushPending(.{ .sgr = .dim_on }),
                3 => self.pushPending(.{ .sgr = .italic_on }),
                23 => self.pushPending(.{ .sgr = .italic_off }),
                4 => self.pushPending(.{ .sgr = .underline_on }),
                24 => self.pushPending(.{ .sgr = .underline_off }),
                7 => self.pushPending(.{ .sgr = .reverse_on }),
                27 => self.pushPending(.{ .sgr = .reverse_off }),
                9 => self.pushPending(.{ .sgr = .strikethrough_on }),
                29 => self.pushPending(.{ .sgr = .strikethrough_off }),
                22 => {
                    self.pushPending(.{ .sgr = .bold_off });
                    self.pushPending(.{ .sgr = .dim_off });
                },
                39 => self.pushPending(.{ .sgr = .{ .fg = .default } }),
                49 => self.pushPending(.{ .sgr = .{ .bg = .default } }),
                30...37 => self.pushPending(.{ .sgr = .{ .fg = state_mod.ansiNamed(code - 30, false) } }),
                40...47 => self.pushPending(.{ .sgr = .{ .bg = state_mod.ansiNamed(code - 40, false) } }),
                90...97 => self.pushPending(.{ .sgr = .{ .fg = state_mod.ansiNamed(code - 90, true) } }),
                100...107 => self.pushPending(.{ .sgr = .{ .bg = state_mod.ansiNamed(code - 100, true) } }),
                38, 48 => {
                    if (self.extendedColorAction(code == 38, &index)) |action| {
                        self.pushPending(action);
                    }
                },
                else => {},
            }
            index += 1;
        }

        if (self.pending_len == 0) return .{ .sgr = .reset };
        const first = self.pending[0];
        self.pending_index = 1;
        return first;
    }

    fn paramOr(self: *const Parser, index: usize, fallback: usize) usize {
        if (index >= self.params_len) return fallback;
        return self.params[index] orelse fallback;
    }

    fn resetParams(self: *Parser) void {
        self.params_len = 0;
        self.csi_dollar = false;
        self.params = [_]?usize{null} ** self.params.len;
    }

    fn pushPending(self: *Parser, action: action_mod.Action) void {
        if (self.pending_len < self.pending.len) {
            self.pending[self.pending_len] = action;
            self.pending_len += 1;
        }
    }

    fn extendedColorAction(self: *Parser, fg: bool, index: *usize) ?action_mod.Action {
        const mode = self.paramOr(index.* + 1, 0);
        switch (mode) {
            5 => {
                const value = self.paramOr(index.* + 2, 0);
                index.* += 2;
                return .{ .sgr = if (fg) .{ .fg = .{ .indexed = @intCast(@min(value, 255)) } } else .{ .bg = .{ .indexed = @intCast(@min(value, 255)) } } };
            },
            2 => {
                const r = self.paramOr(index.* + 2, 0);
                const g = self.paramOr(index.* + 3, 0);
                const b = self.paramOr(index.* + 4, 0);
                index.* += 4;
                const rgb: @import("color.zig").Rgb = .{
                    .r = @intCast(@min(r, 255)),
                    .g = @intCast(@min(g, 255)),
                    .b = @intCast(@min(b, 255)),
                };
                return .{ .sgr = if (fg) .{ .fg = .{ .rgb = rgb } } else .{ .bg = .{ .rgb = rgb } } };
            },
            else => return null,
        }
    }

    fn dispatchOsc(self: *Parser) action_mod.Action {
        if (self.osc_overflow) return .nop;
        const payload = self.osc_buf[0..self.osc_len];
        if (payload.len == 0) return .nop;

        const semi = std.mem.indexOfScalar(u8, payload, ';') orelse return .nop;
        const code = std.fmt.parseInt(u16, payload[0..semi], 10) catch return .nop;
        const rest = payload[semi + 1 ..];

        return switch (code) {
            0, 2 => .{ .set_title = rest },
            4 => self.parseOscPaletteQuery(rest),
            7 => .{ .set_cwd = rest },
            10 => if (std.mem.eql(u8, rest, "?")) .{ .query_color = .foreground } else .nop,
            11 => if (std.mem.eql(u8, rest, "?")) .{ .query_color = .background } else .nop,
            12 => if (std.mem.eql(u8, rest, "?")) .{ .query_color = .cursor } else .nop,
            else => .nop,
        };
    }

    fn parseOscPaletteQuery(_: *Parser, rest: []const u8) action_mod.Action {
        const semi = std.mem.indexOfScalar(u8, rest, ';') orelse return .nop;
        if (!std.mem.eql(u8, rest[semi + 1 ..], "?")) return .nop;
        const idx = std.fmt.parseInt(u8, rest[0..semi], 10) catch return .nop;
        return .{ .query_palette_color = idx };
    }
};

test "parser handles cursor and sgr subset" {
    var parser: Parser = .{};
    _ = parser.next(0x1B);
    _ = parser.next('[');
    _ = parser.next('3');
    _ = parser.next('1');
    const action = parser.next('m').?;
    switch (action) {
        .sgr => {},
        else => return error.UnexpectedAction,
    }
}

test "parser expands multi-sgr sequence" {
    var parser: Parser = .{};
    _ = parser.next(0x1B);
    _ = parser.next('[');
    _ = parser.next('1');
    _ = parser.next(';');
    _ = parser.next('4');
    const first = parser.next('m').?;
    const second = parser.next('x').?;
    switch (first) {
        .sgr => |sgr| try std.testing.expect(sgr == .bold_on),
        else => return error.UnexpectedAction,
    }
    switch (second) {
        .sgr => |sgr| try std.testing.expect(sgr == .underline_on),
        else => return error.UnexpectedAction,
    }
}

test "parser supports indexed and rgb sgr" {
    var parser: Parser = .{};
    const seq = "\x1b[38;5;208m";
    for (seq[0 .. seq.len - 1]) |byte| _ = parser.next(byte);
    const indexed = parser.next(seq[seq.len - 1]).?;
    switch (indexed) {
        .sgr => |sgr| switch (sgr) {
            .fg => |color| switch (color) {
                .indexed => |value| try std.testing.expectEqual(@as(u8, 208), value),
                else => return error.UnexpectedColor,
            },
            else => return error.UnexpectedSgr,
        },
        else => return error.UnexpectedAction,
    }

    parser = .{};
    const rgb_seq = "\x1b[48;2;1;2;3m";
    for (rgb_seq[0 .. rgb_seq.len - 1]) |byte| _ = parser.next(byte);
    const rgb = parser.next(rgb_seq[rgb_seq.len - 1]).?;
    switch (rgb) {
        .sgr => |sgr| switch (sgr) {
            .bg => |color| switch (color) {
                .rgb => |value| {
                    try std.testing.expectEqual(@as(u8, 1), value.r);
                    try std.testing.expectEqual(@as(u8, 2), value.g);
                    try std.testing.expectEqual(@as(u8, 3), value.b);
                },
                else => return error.UnexpectedColor,
            },
            else => return error.UnexpectedSgr,
        },
        else => return error.UnexpectedAction,
    }
}

test "parser recognizes erase chars" {
    var parser: Parser = .{};
    const seq = "\x1b[31X";
    for (seq[0 .. seq.len - 1]) |byte| _ = parser.next(byte);
    const action = parser.next(seq[seq.len - 1]).?;
    switch (action) {
        .erase_chars => |count| try std.testing.expectEqual(@as(usize, 31), count),
        else => return error.UnexpectedAction,
    }
}

test "parser recognizes form feed" {
    var parser = Parser{};
    const action = parser.next(0x0C).?;
    switch (action) {
        .form_feed => {},
        else => return error.UnexpectedAction,
    }
}

test "parser recognizes cursor style" {
    var parser: Parser = .{};
    const seq = "\x1b[5 q";
    for (seq[0 .. seq.len - 1]) |byte| _ = parser.next(byte);
    const action = parser.next(seq[seq.len - 1]).?;
    switch (action) {
        .set_cursor_shape => |shape| try std.testing.expect(shape == .bar),
        else => return error.UnexpectedAction,
    }
}

test "parser does not leave stale pending action after single sgr" {
    var parser: Parser = .{};
    _ = parser.next(0x1B);
    _ = parser.next('[');
    _ = parser.next('1');
    const first = parser.next('m').?;
    switch (first) {
        .sgr => |sgr| try std.testing.expect(sgr == .bold_on),
        else => return error.UnexpectedAction,
    }

    const esc = parser.next(0x1B);
    try std.testing.expect(esc == null);
    const bracket = parser.next('[');
    try std.testing.expect(bracket == null);
    const row = parser.next('6');
    try std.testing.expect(row == null);
    _ = parser.next(';');
    _ = parser.next('2');
    const move = parser.next('H').?;
    switch (move) {
        .cursor_position => |pos| {
            try std.testing.expectEqual(@as(usize, 5), pos.row);
            try std.testing.expectEqual(@as(usize, 1), pos.col);
        },
        else => return error.UnexpectedAction,
    }
}

test "parser supports save restore and cursor visibility" {
    var parser: Parser = .{};
    _ = parser.next(0x1B);
    try std.testing.expectEqual(action_mod.Action.save_cursor, parser.next('7').?);

    parser = .{};
    _ = parser.next(0x1B);
    try std.testing.expectEqual(action_mod.Action.reverse_index, parser.next('M').?);

    parser = .{};
    _ = parser.next(0x1B);
    _ = parser.next('[');
    _ = parser.next('?');
    _ = parser.next('7');
    const nowrap = parser.next('l').?;
    switch (nowrap) {
        .auto_wrap => |enabled| try std.testing.expect(!enabled),
        else => return error.UnexpectedAction,
    }

    parser = .{};
    _ = parser.next(0x1B);
    _ = parser.next('[');
    _ = parser.next('?');
    _ = parser.next('2');
    _ = parser.next('5');
    const hide = parser.next('l').?;
    switch (hide) {
        .cursor_visible => |visible| try std.testing.expect(!visible),
        else => return error.UnexpectedAction,
    }
}

test "parser recognizes scroll region" {
    var parser: Parser = .{};
    const seq = "\x1b[2;10r";
    for (seq[0 .. seq.len - 1]) |byte| _ = parser.next(byte);
    const action = parser.next(seq[seq.len - 1]).?;
    switch (action) {
        .set_scroll_region => |region| {
            try std.testing.expectEqual(@as(usize, 2), region.top);
            try std.testing.expectEqual(@as(usize, 10), region.bottom);
        },
        else => return error.UnexpectedAction,
    }
}

test "parser consumes osc title and cwd" {
    var parser: Parser = .{};
    const title_seq = "\x1b]0;FMUS demo\x07";
    for (title_seq[0 .. title_seq.len - 1]) |byte| _ = parser.next(byte);
    const title = parser.next(title_seq[title_seq.len - 1]).?;
    switch (title) {
        .set_title => |value| try std.testing.expectEqualStrings("FMUS demo", value),
        else => return error.UnexpectedAction,
    }

    parser = .{};
    const cwd_seq = "\x1b]7;C:\\\\work\x1b\\";
    for (cwd_seq[0 .. cwd_seq.len - 1]) |byte| _ = parser.next(byte);
    const cwd = parser.next(cwd_seq[cwd_seq.len - 1]).?;
    switch (cwd) {
        .set_cwd => |value| try std.testing.expectEqualStrings("C:\\\\work", value),
        else => return error.UnexpectedAction,
    }
}

test "parser recognizes device reports and alternate screen" {
    var parser: Parser = .{};
    const dsr_seq = "\x1b[6n";
    for (dsr_seq[0 .. dsr_seq.len - 1]) |byte| _ = parser.next(byte);
    const dsr = parser.next(dsr_seq[dsr_seq.len - 1]).?;
    switch (dsr) {
        .device_status_report => |value| try std.testing.expectEqual(@as(usize, 6), value),
        else => return error.UnexpectedAction,
    }

    parser = .{};
    const alt_seq = "\x1b[?1049h";
    for (alt_seq[0 .. alt_seq.len - 1]) |byte| _ = parser.next(byte);
    const alt = parser.next(alt_seq[alt_seq.len - 1]).?;
    switch (alt) {
        .set_alt_screen => |enabled| try std.testing.expect(enabled),
        else => return error.UnexpectedAction,
    }
}

test "parser recognizes kitty keyboard sequences" {
    var parser: Parser = .{};
    const push_seq = "\x1b[>1u";
    for (push_seq[0 .. push_seq.len - 1]) |byte| _ = parser.next(byte);
    const push = parser.next(push_seq[push_seq.len - 1]).?;
    switch (push) {
        .kitty_push_flags => |flags| try std.testing.expectEqual(@as(u5, 1), flags),
        else => return error.UnexpectedAction,
    }

    parser = .{};
    const pop_seq = "\x1b[<2u";
    for (pop_seq[0 .. pop_seq.len - 1]) |byte| _ = parser.next(byte);
    const pop = parser.next(pop_seq[pop_seq.len - 1]).?;
    switch (pop) {
        .kitty_pop_flags => |count| try std.testing.expectEqual(@as(u8, 2), count),
        else => return error.UnexpectedAction,
    }

    parser = .{};
    const query_seq = "\x1b[?u";
    for (query_seq[0 .. query_seq.len - 1]) |byte| _ = parser.next(byte);
    const query = parser.next(query_seq[query_seq.len - 1]).?;
    try std.testing.expect(query == .kitty_query_flags);
}

test "parser recognizes keypad, decrqm, and osc color queries" {
    var parser: Parser = .{};
    _ = parser.next(0x1B);
    try std.testing.expect(parser.next('=').? == .set_keypad_app_mode);

    parser = .{};
    const decrqm_seq = "\x1b[?2026$p";
    for (decrqm_seq[0 .. decrqm_seq.len - 1]) |byte| _ = parser.next(byte);
    const mode = parser.next(decrqm_seq[decrqm_seq.len - 1]).?;
    switch (mode) {
        .query_dec_private_mode => |value| try std.testing.expectEqual(@as(u16, 2026), value),
        else => return error.UnexpectedAction,
    }

    parser = .{};
    const color_seq = "\x1b]10;?\x07";
    for (color_seq[0 .. color_seq.len - 1]) |byte| _ = parser.next(byte);
    const color = parser.next(color_seq[color_seq.len - 1]).?;
    switch (color) {
        .query_color => |target| try std.testing.expect(target == .foreground),
        else => return error.UnexpectedAction,
    }
}

test "parser recognizes bracketed paste and mouse modes" {
    var parser = Parser{};
    _ = parser.next(0x1b);
    _ = parser.next('[');
    _ = parser.next('?');
    _ = parser.next('2');
    _ = parser.next('0');
    _ = parser.next('0');
    _ = parser.next('4');
    try std.testing.expectEqualDeep(action_mod.Action{ .bracketed_paste = true }, parser.next('h').?);

    _ = parser.next(0x1b);
    _ = parser.next('[');
    _ = parser.next('?');
    _ = parser.next('1');
    _ = parser.next('0');
    _ = parser.next('0');
    _ = parser.next('6');
    try std.testing.expectEqualDeep(action_mod.Action{ .mouse_sgr = true }, parser.next('h').?);

    _ = parser.next(0x1b);
    _ = parser.next('[');
    _ = parser.next('?');
    _ = parser.next('1');
    _ = parser.next('0');
    _ = parser.next('0');
    _ = parser.next('3');
    try std.testing.expectEqualDeep(action_mod.Action{ .mouse_tracking = .any_event }, parser.next('h').?);
}
