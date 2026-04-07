const std = @import("std");
const action_mod = @import("action.zig");
const platform = @import("../platform.zig");
const key_encode = @import("key_encode.zig");

pub const MouseTrackingMode = action_mod.MouseTrackingMode;

pub const MouseButton = enum {
    left,
    middle,
    right,
    none,
};

pub const MouseEventKind = enum {
    press,
    release,
    move,
    scroll_up,
    scroll_down,
};

pub const MouseEvent = struct {
    kind: MouseEventKind,
    button: MouseButton = .none,
    x: u16 = 1,
    y: u16 = 1,
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

pub const InputError = error{BufferTooSmall};

pub fn wrapPaste(enabled: bool, text: []const u8, out: []u8) InputError![]const u8 {
    if (!enabled) {
        if (out.len < text.len) return error.BufferTooSmall;
        @memcpy(out[0..text.len], text);
        return out[0..text.len];
    }
    const prefix = "\x1b[200~";
    const suffix = "\x1b[201~";
    const total = prefix.len + text.len + suffix.len;
    if (out.len < total) return error.BufferTooSmall;
    @memcpy(out[0..prefix.len], prefix);
    @memcpy(out[prefix.len..][0..text.len], text);
    @memcpy(out[prefix.len + text.len..][0..suffix.len], suffix);
    return out[0..total];
}

pub fn encodeMouse(tracking: MouseTrackingMode, sgr_enabled: bool, ev: MouseEvent, out: []u8) []const u8 {
    if (tracking == .off) return out[0..0];
    if (!sgr_enabled) return out[0..0];
    if (ev.kind == .move) {
        switch (tracking) {
            .off, .x10 => return out[0..0],
            .button_event => if (ev.button == .none) return out[0..0],
            .any_event => {},
        }
    }

    var cb: u8 = switch (ev.kind) {
        .press, .release => switch (ev.button) {
            .left => @as(u8, 0),
            .middle => 1,
            .right => 2,
            .none => 0,
        },
        .move => switch (ev.button) {
            .left => @as(u8, 32),
            .middle => 33,
            .right => 34,
            .none => 35,
        },
        .scroll_up => 64,
        .scroll_down => 65,
    };

    if (ev.shift) cb += 4;
    if (ev.alt) cb += 8;
    if (ev.ctrl) cb += 16;

    const final: u8 = if (ev.kind == .release) 'm' else 'M';
    return std.fmt.bufPrint(out, "\x1b[<{d};{d};{d}{c}", .{ cb, ev.x, ev.y, final }) catch out[0..0];
}

pub fn modifiersFromPlatform(mods: platform.KeyModifiers) key_encode.Modifiers {
    return .{
        .shift = mods.shift,
        .alt = mods.alt,
        .ctrl = mods.ctrl,
        .super_key = mods.super_key,
    };
}

pub fn keyEventFromVKey(vkey: u32, mods: platform.KeyModifiers) ?key_encode.KeyEvent {
    const mapped = switch (vkey) {
        0x08 => key_encode.KeyCode.backspace,
        0x09 => key_encode.KeyCode.tab,
        0x0D => key_encode.KeyCode.enter,
        0x1B => key_encode.KeyCode.escape,
        0x21 => key_encode.KeyCode.page_up,
        0x22 => key_encode.KeyCode.page_down,
        0x23 => key_encode.KeyCode.end,
        0x24 => key_encode.KeyCode.home,
        0x25 => key_encode.KeyCode.left,
        0x26 => key_encode.KeyCode.up,
        0x27 => key_encode.KeyCode.right,
        0x28 => key_encode.KeyCode.down,
        0x2D => key_encode.KeyCode.insert,
        0x2E => key_encode.KeyCode.delete,
        0x70 => key_encode.KeyCode.f1,
        0x71 => key_encode.KeyCode.f2,
        0x72 => key_encode.KeyCode.f3,
        0x73 => key_encode.KeyCode.f4,
        0x74 => key_encode.KeyCode.f5,
        0x75 => key_encode.KeyCode.f6,
        0x76 => key_encode.KeyCode.f7,
        0x77 => key_encode.KeyCode.f8,
        0x78 => key_encode.KeyCode.f9,
        0x79 => key_encode.KeyCode.f10,
        0x7A => key_encode.KeyCode.f11,
        0x7B => key_encode.KeyCode.f12,
        else => null,
    };
    if (mapped) |key| {
        return .{ .key = key, .mods = modifiersFromPlatform(mods) };
    }

    if ((mods.ctrl or mods.alt) and !mods.super_key) {
        if (printableCodepointFromVKey(vkey, mods)) |cp| {
            return .{
                .key = .codepoint,
                .mods = modifiersFromPlatform(mods),
                .codepoint = cp,
            };
        }
    }
    return null;
}

pub fn charEvent(codepoint: u21, mods: platform.KeyModifiers) ?key_encode.KeyEvent {
    if (mods.super_key) return null;
    if (codepoint < 0x20 and codepoint != '\r' and codepoint != '\t' and codepoint != '\n') return null;
    return .{
        .key = .codepoint,
        .mods = modifiersFromPlatform(mods),
        .codepoint = switch (codepoint) {
            '\n' => '\r',
            else => codepoint,
        },
    };
}

pub fn suppressCharAfterKeyDown(vkey: u32, mods: platform.KeyModifiers) bool {
    if (isModifierOnlyKey(vkey)) return false;
    return keyEventFromVKey(vkey, mods) != null or modifierPrintableHandledByKeydown(vkey, mods);
}

fn isModifierOnlyKey(vkey: u32) bool {
    return switch (vkey) {
        0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5 => true,
        else => false,
    };
}

fn modifierPrintableHandledByKeydown(vkey: u32, mods: platform.KeyModifiers) bool {
    if (mods.super_key) return true;
    if (mods.ctrl and !mods.alt) {
        return switch (vkey) {
            'A'...'Z', 0x20, 0xDB, 0xDC, 0xDD, 0x36, 0xBD, 0xBF => true,
            else => false,
        };
    }
    if (mods.alt and !mods.ctrl) {
        return switch (vkey) {
            'A'...'Z', '0'...'9', 0x20, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE => true,
            else => false,
        };
    }
    return false;
}

fn printableCodepointFromVKey(vkey: u32, mods: platform.KeyModifiers) ?u21 {
    const shift = mods.shift;
    return switch (vkey) {
        'A'...'Z' => if (shift) @intCast(vkey) else @intCast(vkey - 'A' + 'a'),
        '0'...'9' => @intCast(vkey),
        0x20 => ' ',
        0xDB => '[',
        0xDC => '\\',
        0xDD => ']',
        0xBA => ';',
        0xBB => '=',
        0xBC => ',',
        0xBD => '-',
        0xBE => '.',
        0xBF => '/',
        0xC0 => '`',
        0xDE => '\'',
        else => null,
    };
}

test "input exposes special key events and suppression" {
    try std.testing.expectEqual(key_encode.KeyCode.enter, keyEventFromVKey(0x0D, .{}).?.key);
    try std.testing.expect(charEvent('a', .{}).?.key == .codepoint);
    try std.testing.expect(suppressCharAfterKeyDown(0x0D, .{}));
    try std.testing.expect(suppressCharAfterKeyDown('C', .{ .ctrl = true }));
    try std.testing.expectEqual(@as(u21, 'c'), keyEventFromVKey('C', .{ .ctrl = true }).?.codepoint);
    try std.testing.expectEqual(@as(u21, 'D'), keyEventFromVKey('D', .{ .ctrl = true, .shift = true }).?.codepoint);
    try std.testing.expect(!suppressCharAfterKeyDown('A', .{}));
}

test "wrapPaste enabled wraps with brackets" {
    var buf: [64]u8 = undefined;
    const result = try wrapPaste(true, "abc", &buf);
    try std.testing.expectEqualStrings("\x1b[200~abc\x1b[201~", result);
}

test "encodeMouse emits sgr sequence" {
    var buf: [64]u8 = undefined;
    const result = encodeMouse(.x10, true, .{
        .kind = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    }, &buf);
    try std.testing.expectEqualStrings("\x1b[<0;10;5M", result);
}

test "encodeMouse emits drag sequence for button event mode" {
    var buf: [64]u8 = undefined;
    const result = encodeMouse(.button_event, true, .{
        .kind = .move,
        .button = .left,
        .x = 12,
        .y = 6,
    }, &buf);
    try std.testing.expectEqualStrings("\x1b[<32;12;6M", result);
}
