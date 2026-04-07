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

const AppContext = struct {
    allocator: std.mem.Allocator,
    service: fmus.terminal.AutomationService.Service,
    runtime: ?*fmus.terminal.Runtime = null,
};

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = trace;
    _ = ret_addr;
    if (std.fs.createFileAbsolute("C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\terminal-automation-demo-panic.log", .{ .truncate = true })) |file| {
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

    config.title = "FMUS Terminal Automation Demo";
    config.class_name = "FMUSTerminalAutomationDemoWindow";
    config.rows = 30;
    config.cols = 110;
    config.width = 1120;
    config.height = 760;
    config.icon_path = try demoIconPath(allocator);
    config.show_automation_button = true;

    var app = AppContext{
        .allocator = allocator,
        .service = fmus.terminal.AutomationService.Service.init(allocator, .{
            .address = "127.0.0.1",
            .port = 9311,
            .protocol = "fmus.automation.v1",
            .event_log_path = "C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\automation-events.jsonl",
        }),
    };
    defer app.service.deinit();
    defer if (config.icon_path) |path| allocator.free(path);

    config.ui_action_ctx = &app;
    config.on_ui_action = onUiAction;

    var runtime = try fmus.terminal.Runtime.init(allocator, config);
    defer runtime.deinit();
    app.runtime = &runtime;

    try runtime.spawnDefaultShell();
    if (shouldAutostartAutomation()) {
        _ = try app.service.start(&runtime);
        try runtime.showStatus("Automation WS server started on ws://127.0.0.1:9311");
    } else {
        try runtime.showStatus("Click Serve in the toolbar to start WS automation on ws://127.0.0.1:9311");
    }
    try runtime.run();
}

fn onUiAction(ctx: *anyopaque, action: fmus.terminal.runtime.Config.UiAction) !void {
    const app: *AppContext = @ptrCast(@alignCast(ctx));
    switch (action) {
        .automation_server => {
            if (app.service.isStarted()) {
                try app.runtime.?.showStatus("Automation WS server already running on ws://127.0.0.1:9311");
                return;
            }
            _ = try app.service.start(app.runtime.?);
            const endpoint = try app.service.endpointAlloc(app.allocator);
            defer app.allocator.free(endpoint);
            const message = try std.fmt.allocPrint(app.allocator, "Automation WS server started on {s}", .{endpoint});
            defer app.allocator.free(message);
            try app.runtime.?.showStatus(message);
        },
    }
}

fn demoIconPath(allocator: std.mem.Allocator) !?[]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);
    return try std.fs.path.join(allocator, &.{ exe_dir, "fmus-terminal-demo.ico" });
}

fn shouldAutostartAutomation() bool {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "FMUS_AUTOMATION_AUTOSTART") catch return false;
    defer std.heap.page_allocator.free(value);
    const trimmed = std.mem.trim(u8, value, " \r\t");
    if (trimmed.len == 0) return false;
    return std.mem.eql(u8, trimmed, "1") or std.ascii.eqlIgnoreCase(trimmed, "true") or std.ascii.eqlIgnoreCase(trimmed, "yes");
}

fn vectoredHandler(info: *EXCEPTION_POINTERS) callconv(.winapi) LONG {
    if (std.fs.createFileAbsolute("C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\terminal-automation-demo-exception.log", .{ .truncate = true })) |file| {
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
