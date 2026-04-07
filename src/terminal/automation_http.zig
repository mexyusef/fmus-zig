const std = @import("std");
const automation_mod = @import("automation.zig");
const automation_ws = @import("automation_ws.zig");
const http_server = @import("../http_server.zig");

pub fn handleRequestAlloc(host: *automation_mod.AutomationHost, allocator: std.mem.Allocator, request: http_server.Request) !http_server.Response {
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.target, "/automation/capabilities")) {
        var result = try host.execute(null, .get_capabilities);
        defer result.deinit(allocator);
        return .{
            .status = 200,
            .content_type = "application/json",
            .body = try resultJsonAlloc(allocator, 0, &result),
        };
    }

    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.target, "/automation/replay")) {
        var result = try host.execute(null, .replay_events);
        defer result.deinit(allocator);
        return .{
            .status = 200,
            .content_type = "application/json",
            .body = try resultJsonAlloc(allocator, 0, &result),
        };
    }

    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.target, "/automation/primary-session")) {
        var result = try host.execute(null, .get_primary_session);
        defer result.deinit(allocator);
        return .{
            .status = 200,
            .content_type = "application/json",
            .body = try resultJsonAlloc(allocator, 0, &result),
        };
    }

    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.target, "/automation/sessions")) {
        var result = try host.execute(null, .list_sessions);
        defer result.deinit(allocator);
        return .{
            .status = 200,
            .content_type = "application/json",
            .body = try resultJsonAlloc(allocator, 0, &result),
        };
    }

    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.target, "/automation/command")) {
        return .{
            .status = 200,
            .content_type = "application/json",
            .body = try automation_ws.dispatchRequestAlloc(host, allocator, request.body),
        };
    }

    if (std.mem.eql(u8, request.method, "GET")) {
        if (try maybeHandleSessionGet(host, allocator, request.target)) |response| return response;
    }

    return .{
        .status = 404,
        .content_type = "application/json",
        .body = try allocator.dupe(u8, "{\"ok\":false,\"error\":{\"message\":\"not found\"}}"),
    };
}

fn maybeHandleSessionGet(host: *automation_mod.AutomationHost, allocator: std.mem.Allocator, target: []const u8) !?http_server.Response {
    const prefix = "/automation/sessions/";
    if (!std.mem.startsWith(u8, target, prefix)) return null;
    const tail = target[prefix.len..];
    const slash = std.mem.indexOfScalar(u8, tail, '/') orelse return null;
    const id = std.fmt.parseInt(automation_mod.SessionId, tail[0..slash], 10) catch return null;
    const action = tail[slash + 1 ..];

    const cmd: automation_mod.Command =
        if (std.mem.eql(u8, action, "capabilities")) .get_capabilities
        else if (std.mem.eql(u8, action, "visible-text")) .get_visible_text
        else if (std.mem.eql(u8, action, "scrollback-text")) .get_scrollback_text
        else if (std.mem.eql(u8, action, "visible-buffer")) .get_visible_buffer
        else if (std.mem.eql(u8, action, "scrollback-buffer")) .get_scrollback_buffer
        else if (std.mem.eql(u8, action, "metrics")) .get_metrics
        else if (std.mem.eql(u8, action, "shell-state")) .get_shell_state
        else if (std.mem.eql(u8, action, "title")) .get_title
        else if (std.mem.eql(u8, action, "cwd")) .get_cwd
        else if (std.mem.eql(u8, action, "process")) .get_process
        else if (std.mem.eql(u8, action, "last-command")) .get_last_command
        else if (std.mem.eql(u8, action, "last-exit-code")) .get_last_exit_code
        else if (std.mem.eql(u8, action, "input-log")) .get_input_log
        else if (std.mem.eql(u8, action, "command-history")) .get_command_history
        else return null;

    var result = host.execute(id, cmd) catch |err| {
        return .{
            .status = 400,
            .content_type = "application/json",
            .body = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"error\":{{\"message\":\"{s}\"}}}}", .{@errorName(err)}),
        };
    };
    defer result.deinit(allocator);
    return .{
        .status = 200,
        .content_type = "application/json",
        .body = try resultJsonAlloc(allocator, 0, &result),
    };
}

fn resultJsonAlloc(allocator: std.mem.Allocator, id: u64, result: *automation_mod.Result) ![]u8 {
    switch (result.*) {
        .none => return okAlloc(allocator, .{ .id = id }),
        .session_id => |value| return okAlloc(allocator, .{ .id = id, .session_id = value }),
        .generation => |value| return okAlloc(allocator, .{ .id = id, .generation = value }),
        .text => |value| return okAlloc(allocator, .{ .id = id, .text = value }),
        .buffer => |value| return okAlloc(allocator, .{ .id = id, .buffer = value }),
        .shell_state => |value| return okAlloc(allocator, .{ .id = id, .shell_state = value }),
        .cursor => |value| return okAlloc(allocator, .{ .id = id, .cursor = value }),
        .metrics => |value| return okAlloc(allocator, .{ .id = id, .metrics = value }),
        .process => |value| return okAlloc(allocator, .{ .id = id, .process = value }),
        .last_exit_code => |value| return okAlloc(allocator, .{ .id = id, .last_exit_code = value }),
        .capabilities => |value| return okAlloc(allocator, .{ .id = id, .capabilities = value }),
        .input_log => |value| return okAlloc(allocator, .{ .id = id, .input_log = value }),
        .command_history => |value| return okAlloc(allocator, .{ .id = id, .command_history = value }),
        .sessions => |value| return okAlloc(allocator, .{ .id = id, .sessions = value }),
        .events => |value| return okAlloc(allocator, .{ .id = id, .events = value }),
        .replay => |value| return okAlloc(allocator, .{ .id = id, .replay = value }),
    }
}

fn okAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(.{ .ok = true, .result = value }, .{}, &out.writer);
    return allocator.dupe(u8, out.written());
}

test "automation http handles sessions list" {
    var host = automation_mod.AutomationHost.init(std.testing.allocator, .{});
    defer host.deinit();

    var runtime = try @import("runtime.zig").Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    _ = try host.attachRuntime(&runtime);

    const response = try handleRequestAlloc(&host, std.testing.allocator, .{
        .method = "GET",
        .target = "/automation/sessions",
        .body = "",
        .raw = "",
    });
    defer std.testing.allocator.free(response.body);
    try std.testing.expectEqual(@as(u16, 200), response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"sessions\"") != null);
}

test "automation http handles capabilities route" {
    var host = automation_mod.AutomationHost.init(std.testing.allocator, .{});
    defer host.deinit();

    var runtime = try @import("runtime.zig").Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    _ = try host.attachRuntime(&runtime);

    const response = try handleRequestAlloc(&host, std.testing.allocator, .{
        .method = "GET",
        .target = "/automation/sessions/1/capabilities",
        .body = "",
        .raw = "",
    });
    defer std.testing.allocator.free(response.body);
    try std.testing.expectEqual(@as(u16, 200), response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"capabilities\"") != null);
}
