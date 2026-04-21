const std = @import("std");
const ziggy = @import("ziggy");

const DWORD = std.os.windows.DWORD;
const HANDLE = std.os.windows.HANDLE;
const SHORT = std.os.windows.SHORT;
const BOOL = std.os.windows.BOOL;
const WAIT_OBJECT_0: DWORD = 0;
const WAIT_TIMEOUT: DWORD = 258;

const COORD = extern struct {
    X: SHORT,
    Y: SHORT,
};

const SMALL_RECT = extern struct {
    Left: SHORT,
    Top: SHORT,
    Right: SHORT,
    Bottom: SHORT,
};

const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: u16,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

extern "kernel32" fn GetConsoleScreenBufferInfo(
    hConsoleOutput: HANDLE,
    lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO,
) callconv(.winapi) BOOL;
extern "kernel32" fn WaitForSingleObject(
    hHandle: HANDLE,
    dwMilliseconds: DWORD,
) callconv(.winapi) DWORD;

pub fn detectTerminalSize() ziggy.Size {
    if (@import("builtin").os.tag == .windows) {
        if (queryConsoleSize(std.fs.File.stdout().handle)) |size| return size;
        if (std.fs.cwd().openFile("CONOUT$", .{ .mode = .read_write })) |conout| {
            defer conout.close();
            if (queryConsoleSize(conout.handle)) |size| return size;
        } else |_| {}
        if (queryConsoleSize(std.fs.File.stderr().handle)) |size| return size;
    }
    return .{ .width = 120, .height = 40 };
}

fn queryConsoleSize(handle: HANDLE) ?ziggy.Size {
    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (GetConsoleScreenBufferInfo(handle, &info) == 0) return null;
    const width = @as(u16, @intCast(@max(@as(i32, 1), @as(i32, info.srWindow.Right) - @as(i32, info.srWindow.Left) + 1)));
    const height = @as(u16, @intCast(@max(@as(i32, 1), @as(i32, info.srWindow.Bottom) - @as(i32, info.srWindow.Top) + 1)));
    return .{ .width = width, .height = height };
}

pub fn readEvent(allocator: std.mem.Allocator, stdin_file: std.fs.File) !?ziggy.Event {
    var buffer: [512]u8 = undefined;
    const read_len = try stdin_file.read(&buffer);
    if (read_len == 0) return null;
    const bytes = buffer[0..read_len];
    if (try ziggy.parseBracketedPaste(allocator, bytes)) |parsed| return parsed.event;
    if (ziggy.parseOne(bytes)) |parsed| return parsed.event;
    return null;
}

pub fn runInteractiveProgram(
    comptime Model: type,
    comptime Msg: type,
    allocator: std.mem.Allocator,
    model: Model,
    options: ziggy.RootOptions,
) !void {
    _ = ziggy.prepareConsole();

    const stdin_file = std.fs.File.stdin();
    const stdout_file = std.fs.File.stdout();
    var stdin_buffer: [4096]u8 = undefined;
    var stdout_buffer: [4096]u8 = undefined;
    var stdin_reader = stdin_file.reader(&stdin_buffer);
    var stdout_writer = stdout_file.writer(&stdout_buffer);
    const size = detectTerminalSize();
    var tty = ziggy.Tty.withCapabilities(
        &stdin_reader.interface,
        &stdout_writer.interface,
        size,
        .{
            .alternate_screen = true,
            .bracketed_paste = true,
            .mouse = true,
            .synchronized_output = true,
            .terminal_title = true,
        },
    );
    tty.output_file = stdout_file;

    var program = try ziggy.Program(Model, Msg).init(allocator, tty, model, options);
    defer program.deinit();
    try program.start();
    defer program.tty.leaveRawMode();

    var last_size = size;
    while (true) {
        if (@import("builtin").os.tag == .windows) {
            const wait_result = WaitForSingleObject(stdin_file.handle, 50);
            const current_size = detectTerminalSize();
            if (current_size.width != last_size.width or current_size.height != last_size.height) {
                last_size = current_size;
                const keep_running = try program.processTerminalEvent(.{ .resize = .{
                    .width = current_size.width,
                    .height = current_size.height,
                } });
                if (!keep_running) break;
            }
            if (wait_result == WAIT_TIMEOUT) continue;
            if (wait_result != WAIT_OBJECT_0) break;
        }

        const maybe_event = try readEvent(allocator, stdin_file);
        if (maybe_event == null) break;
        const keep_running = try program.processTerminalEvent(maybe_event.?);
        if (!keep_running) break;
    }
}
