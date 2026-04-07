const std = @import("std");
const automation_mod = @import("automation.zig");
const runtime_mod = @import("runtime.zig");
const ws_mod = @import("../ws.zig");

pub const Config = struct {
    address: []const u8 = "127.0.0.1",
    port: u16 = 9311,
    protocol: ?[]const u8 = "fmus.automation.v1",
};

pub const Request = struct {
    id: u64 = 0,
    method: []const u8,
    session_id: ?automation_mod.SessionId = null,
    text: ?[]const u8 = null,
    path: ?[]const u8 = null,
    ctrl: ?u8 = null,
    rows: ?usize = null,
    cols: ?usize = null,
    x: ?i32 = null,
    y: ?i32 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    since_generation: ?u64 = null,
    cwd: ?[]const u8 = null,
    title: ?[]const u8 = null,
};

pub const AutomationWsServer = struct {
    allocator: std.mem.Allocator,
    host: *automation_mod.AutomationHost,
    config: Config,

    pub fn init(allocator: std.mem.Allocator, host: *automation_mod.AutomationHost, config: Config) AutomationWsServer {
        return .{
            .allocator = allocator,
            .host = host,
            .config = config,
        };
    }

    pub fn deinit(_: *AutomationWsServer) void {}

    pub fn listen(self: *AutomationWsServer) !void {
        var server = try std.net.Address.listen(try std.net.Address.parseIp(self.config.address, self.config.port), .{});
        defer server.deinit();
        while (true) {
            const accepted = try server.accept();
            const handshake_buf = try self.allocator.alloc(u8, 8192);
            defer self.allocator.free(handshake_buf);
            var conn = try ws_mod.ServerConn.readAndAccept(self.allocator, accepted.stream, handshake_buf, .{
                .protocol = self.config.protocol,
            });
            defer conn.deinit();
            try self.serveConnection(&conn);
        }
    }

    pub fn listenOnce(self: *AutomationWsServer) !void {
        var server = try std.net.Address.listen(try std.net.Address.parseIp(self.config.address, self.config.port), .{});
        defer server.deinit();
        const accepted = try server.accept();
        const handshake_buf = try self.allocator.alloc(u8, 8192);
        defer self.allocator.free(handshake_buf);
        var conn = try ws_mod.ServerConn.readAndAccept(self.allocator, accepted.stream, handshake_buf, .{
            .protocol = self.config.protocol,
        });
        defer conn.deinit();
        try self.serveConnection(&conn);
    }

    pub fn serveConnection(self: *AutomationWsServer, conn: *ws_mod.ServerConn) !void {
        var scratch: [16 * 1024]u8 = undefined;
        while (true) {
            const msg = conn.receive(&scratch) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            switch (msg) {
                .text => |payload| {
                    defer self.allocator.free(payload);
                    const response = try dispatchRequestAlloc(self.host, self.allocator, payload);
                    defer self.allocator.free(response);
                    try conn.sendText(response);
                },
                .binary => |payload| {
                    defer self.allocator.free(payload);
                    const response = try errorResponseAlloc(self.allocator, 0, "Binary websocket messages are not supported");
                    defer self.allocator.free(response);
                    try conn.sendText(response);
                },
                .close => |close_msg| {
                    defer self.allocator.free(close_msg.reason);
                    break;
                },
            }
        }
    }
};

pub fn dispatchRequestAlloc(host: *automation_mod.AutomationHost, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(Request, allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const req = parsed.value;

    if (std.mem.eql(u8, req.method, "create_shell_session")) {
        var config = runtime_mod.Config{};
        if (req.cwd) |cwd| config.cwd = cwd;
        if (req.title) |title| config.title = title;
        if (req.rows) |rows| config.rows = rows;
        if (req.cols) |cols| config.cols = cols;
        if (req.width) |width| config.width = width;
        if (req.height) |height| config.height = height;
        const id = host.createShellSession(.{ .runtime = config }) catch |err| {
            return errorResponseAlloc(allocator, req.id, @errorName(err));
        };
        return okAlloc(allocator, .{ .id = req.id, .session_id = id });
    }

    var result = host.execute(req.session_id, mapCommand(req) catch |err| {
        return errorResponseAlloc(allocator, req.id, @errorName(err));
    }) catch |err| {
        return errorResponseAlloc(allocator, req.id, @errorName(err));
    };
    defer result.deinit(allocator);

    switch (result) {
        .none => return okAlloc(allocator, .{ .id = req.id }),
        .session_id => |id| return okAlloc(allocator, .{ .id = req.id, .session_id = id }),
        .generation => |generation| return okAlloc(allocator, .{ .id = req.id, .generation = generation }),
        .text => |text| return okAlloc(allocator, .{ .id = req.id, .text = text }),
        .buffer => |buffer| return okAlloc(allocator, .{ .id = req.id, .buffer = buffer }),
        .shell_state => |state| return okAlloc(allocator, .{ .id = req.id, .shell_state = state }),
        .cursor => |cursor| return okAlloc(allocator, .{ .id = req.id, .cursor = cursor }),
        .metrics => |metrics| return okAlloc(allocator, .{ .id = req.id, .metrics = metrics }),
        .process => |process| return okAlloc(allocator, .{ .id = req.id, .process = process }),
        .last_exit_code => |value| return okAlloc(allocator, .{ .id = req.id, .last_exit_code = value }),
        .capabilities => |capabilities| return okAlloc(allocator, .{ .id = req.id, .capabilities = capabilities }),
        .input_log => |items| return okAlloc(allocator, .{ .id = req.id, .input_log = items }),
        .command_history => |items| return okAlloc(allocator, .{ .id = req.id, .command_history = items }),
        .sessions => |sessions| return okAlloc(allocator, .{ .id = req.id, .sessions = sessions }),
        .events => |events| return okAlloc(allocator, .{ .id = req.id, .events = events }),
        .replay => |replay| return okAlloc(allocator, .{ .id = req.id, .replay = replay }),
    }
}

fn mapCommand(req: Request) !automation_mod.Command {
    if (std.mem.eql(u8, req.method, "list_sessions")) return .list_sessions;
    if (std.mem.eql(u8, req.method, "close_session")) return .close_session;
    if (std.mem.eql(u8, req.method, "get_capabilities")) return .get_capabilities;
    if (std.mem.eql(u8, req.method, "get_primary_session")) return .get_primary_session;
    if (std.mem.eql(u8, req.method, "send_text")) return .{ .send_text = req.text orelse return error.MissingText };
    if (std.mem.eql(u8, req.method, "send_ctrl")) return .{ .send_ctrl = req.ctrl orelse return error.MissingCtrl };
    if (std.mem.eql(u8, req.method, "send_escape")) return .{ .send_escape = req.text orelse return error.MissingText };
    if (std.mem.eql(u8, req.method, "resize_terminal")) return .{
        .resize_terminal = .{
            .rows = req.rows orelse return error.MissingRows,
            .cols = req.cols orelse return error.MissingCols,
        },
    };
    if (std.mem.eql(u8, req.method, "set_window_rect")) return .{
        .set_window_rect = .{
            .x = req.x,
            .y = req.y,
            .width = req.width,
            .height = req.height,
        },
    };
    if (std.mem.eql(u8, req.method, "toggle_fullscreen")) return .toggle_fullscreen;
    if (std.mem.eql(u8, req.method, "toggle_zen")) return .toggle_zen;
    if (std.mem.eql(u8, req.method, "get_visible_text")) return .get_visible_text;
    if (std.mem.eql(u8, req.method, "get_scrollback_text")) return .get_scrollback_text;
    if (std.mem.eql(u8, req.method, "get_visible_buffer")) return .get_visible_buffer;
    if (std.mem.eql(u8, req.method, "get_scrollback_buffer")) return .get_scrollback_buffer;
    if (std.mem.eql(u8, req.method, "get_metrics")) return .get_metrics;
    if (std.mem.eql(u8, req.method, "get_shell_state")) return .get_shell_state;
    if (std.mem.eql(u8, req.method, "get_cursor")) return .get_cursor;
    if (std.mem.eql(u8, req.method, "get_title")) return .get_title;
    if (std.mem.eql(u8, req.method, "get_cwd")) return .get_cwd;
    if (std.mem.eql(u8, req.method, "get_process")) return .get_process;
    if (std.mem.eql(u8, req.method, "get_last_command")) return .get_last_command;
    if (std.mem.eql(u8, req.method, "get_last_exit_code")) return .get_last_exit_code;
    if (std.mem.eql(u8, req.method, "get_input_log")) return .get_input_log;
    if (std.mem.eql(u8, req.method, "get_command_history")) return .get_command_history;
    if (std.mem.eql(u8, req.method, "invoke_command")) return .{ .invoke_command = req.text orelse return error.MissingText };
    if (std.mem.eql(u8, req.method, "save_screenshot_png")) return .{ .save_screenshot_png = req.path orelse return error.MissingPath };
    if (std.mem.eql(u8, req.method, "copy_screenshot_clipboard")) return .copy_screenshot_clipboard;
    if (std.mem.eql(u8, req.method, "poll_events")) return .{ .poll_events = req.since_generation orelse 0 };
    if (std.mem.eql(u8, req.method, "replay_events")) return .replay_events;
    return error.UnknownMethod;
}

fn okAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(.{ .ok = true, .result = value }, .{}, &out.writer);
    return allocator.dupe(u8, out.written());
}

fn errorResponseAlloc(allocator: std.mem.Allocator, id: u64, message: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(.{
        .ok = false,
        .id = id,
        .@"error" = .{ .message = message },
    }, .{}, &out.writer);
    return allocator.dupe(u8, out.written());
}

test "automation ws dispatch returns visible text" {
    var host = automation_mod.AutomationHost.init(std.testing.allocator, .{});
    defer host.deinit();

    var runtime = try runtime_mod.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    const id = try host.attachRuntime(&runtime);

    const response = try dispatchRequestAlloc(&host, std.testing.allocator,
        "{ \"id\": 1, \"method\": \"get_title\", \"session_id\": 1 }");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"ok\":true") != null);
    try std.testing.expect(id == 1);
    try std.testing.expect(std.mem.indexOf(u8, response, "FMUS Terminal") != null);
}
