const std = @import("std");
const color_mod = @import("color.zig");

pub const Style = struct {
    fg: color_mod.Color = .default,
    bg: color_mod.Color = .default,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,

    pub fn reset(self: *Style) void {
        self.* = .{};
    }

    pub fn eql(self: Style, other: Style) bool {
        return std.meta.eql(self, other);
    }
};
