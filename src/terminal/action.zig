const color_mod = @import("color.zig");

pub const Sgr = union(enum) {
    reset,
    bold_on,
    bold_off,
    dim_on,
    dim_off,
    italic_on,
    italic_off,
    underline_on,
    underline_off,
    reverse_on,
    reverse_off,
    strikethrough_on,
    strikethrough_off,
    fg: color_mod.Color,
    bg: color_mod.Color,
};

pub const ColorQueryType = enum {
    foreground,
    background,
    cursor,
};

pub const CursorShape = enum {
    block,
    underline,
    bar,
};

pub const ScrollRegion = struct {
    top: usize = 0,
    bottom: usize = 0,
};

pub const MouseTrackingMode = enum {
    off,
    x10,
    button_event,
    any_event,
};

pub const Action = union(enum) {
    nop,
    print: u21,
    carriage_return,
    line_feed,
    backspace,
    tab,
    form_feed,
    set_title: []const u8,
    set_cwd: []const u8,
    set_alt_screen: bool,
    auto_wrap: bool,
    bracketed_paste: bool,
    mouse_tracking: MouseTrackingMode,
    mouse_sgr: bool,
    kitty_push_flags: u5,
    kitty_pop_flags: u8,
    kitty_query_flags,
    query_dec_private_mode: u16,
    query_color: ColorQueryType,
    query_palette_color: u8,
    set_keypad_app_mode,
    reset_keypad_app_mode,
    save_cursor,
    restore_cursor,
    reverse_index,
    cursor_visible: bool,
    primary_device_attributes,
    secondary_device_attributes,
    device_status_report: usize,
    cursor_up: usize,
    cursor_down: usize,
    cursor_forward: usize,
    cursor_backward: usize,
    cursor_horizontal_absolute: usize,
    cursor_vertical_absolute: usize,
    cursor_position: struct {
        row: usize,
        col: usize,
    },
    set_scroll_region: ScrollRegion,
    insert_lines: usize,
    delete_lines: usize,
    insert_chars: usize,
    delete_chars: usize,
    scroll_up: usize,
    scroll_down: usize,
    erase_in_display: usize,
    erase_in_line: usize,
    erase_chars: usize,
    set_cursor_shape: CursorShape,
    sgr: Sgr,
};
