const std = @import("std");
const fmus = @import("fmus");
const builtin = @import("builtin");

const LONG = i32;
const ULONG = u32;
const PVOID = ?*anyopaque;

const EXCEPTION_RECORD = extern struct {
    ExceptionCode: ULONG,
    ExceptionFlags: ULONG,
    ExceptionRecord: ?*EXCEPTION_RECORD,
    ExceptionAddress: PVOID,
    NumberParameters: ULONG,
    ExceptionInformation: [15]usize,
};

const CONTEXT = opaque {};

const EXCEPTION_POINTERS = extern struct {
    ExceptionRecord: *EXCEPTION_RECORD,
    ContextRecord: *CONTEXT,
};

extern "kernel32" fn AddVectoredExceptionHandler(first: ULONG, handler: *const fn (*EXCEPTION_POINTERS) callconv(.winapi) LONG) callconv(.winapi) PVOID;

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = trace;
    _ = ret_addr;
    if (std.fs.createFileAbsolute("C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\terminal-demo-panic.log", .{ .truncate = true })) |file| {
        defer file.close();
        file.writeAll(msg) catch {};
    } else |_| {}
    std.process.exit(1);
}

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        _ = AddVectoredExceptionHandler(1, vectoredHandler);
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var config = fmus.terminal.runtime.Config{};

    if (std.process.getEnvVarOwned(allocator, "FMUS_TERMINAL_STARTUP_INPUT")) |value| {
        defer allocator.free(value);
        config.startup_input = try decodeStartupInput(allocator, value);
    } else |_| {}
    defer if (config.startup_input.len != 0) allocator.free(config.startup_input);

    if (std.process.getEnvVarOwned(allocator, "FMUS_TERMINAL_DEBUG_LOG")) |value| {
        defer allocator.free(value);
        config.debug_log_path = try allocator.dupe(u8, value);
    } else |_| {}
    defer if (config.debug_log_path) |path| allocator.free(path);

    if (std.process.getEnvVarOwned(allocator, "FMUS_TERMINAL_STARTUP_INPUT_MODE")) |value| {
        defer allocator.free(value);
        if (std.ascii.eqlIgnoreCase(value, "window")) {
            config.startup_input_mode = .window_events;
        }
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "FMUS_TERMINAL_THEME")) |value| {
        defer allocator.free(value);
        if (std.ascii.eqlIgnoreCase(value, "mac_bw") or std.ascii.eqlIgnoreCase(value, "macos_bw")) {
            config.theme_preset = .mac_bw;
            config.paint_theme = fmus.terminal.paint.themePreset(.mac_bw);
            config.window_style = fmus.terminal.paint.windowStylePreset(.mac_bw);
        } else if (std.ascii.eqlIgnoreCase(value, "amber")) {
            config.theme_preset = .amber;
            config.paint_theme = fmus.terminal.paint.themePreset(.amber);
            config.window_style = fmus.terminal.paint.windowStylePreset(.amber);
        }
    } else |_| {}

    config.title = "FMUS Terminal Demo";
    config.class_name = "FMUSTerminalDemoWindow";
    config.rows = 30;
    config.cols = 110;
    config.width = 1120;
    config.height = 760;
    config.icon_path = try demoIconPath(allocator);
    defer if (config.icon_path) |path| allocator.free(path);

    try fmus.terminal.Window.runDefaultShellWindow(allocator, config);
}

fn demoIconPath(allocator: std.mem.Allocator) !?[]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);
    return try std.fs.path.join(allocator, &.{ exe_dir, "fmus-terminal-demo.ico" });
}

fn vectoredHandler(info: *EXCEPTION_POINTERS) callconv(.winapi) LONG {
    if (std.fs.createFileAbsolute("C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\terminal-demo-exception.log", .{ .truncate = true })) |file| {
        defer file.close();
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "code=0x{x} addr=0x{x}", .{
            info.ExceptionRecord.ExceptionCode,
            @intFromPtr(info.ExceptionRecord.ExceptionAddress),
        }) catch "";
        file.writeAll(line) catch {};
    } else |_| {}
    return 0;
}

fn decodeStartupInput(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '\\' and i + 1 < value.len) {
            i += 1;
            switch (value[i]) {
                'r' => try out.append(allocator, '\r'),
                'n' => try out.append(allocator, '\n'),
                't' => try out.append(allocator, '\t'),
                'b' => try out.append(allocator, 0x08),
                'e' => try out.append(allocator, 0x1b),
                '\\' => try out.append(allocator, '\\'),
                else => {
                    try out.append(allocator, '\\');
                    try out.append(allocator, value[i]);
                },
            }
            continue;
        }
        try out.append(allocator, value[i]);
    }

    return try out.toOwnedSlice(allocator);
}
