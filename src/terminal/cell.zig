const style_mod = @import("style.zig");

pub const Cell = struct {
    char: u21 = ' ',
    combining: [2]u21 = .{ 0, 0 },
    wide_continuation: bool = false,
    style: style_mod.Style = .{},
};
