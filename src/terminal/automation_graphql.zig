const std = @import("std");
const automation_mod = @import("automation.zig");

pub const Request = struct {
    query: ?[]const u8 = null,
    operationName: ?[]const u8 = null,
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
};

pub fn handleJsonAlloc(host: *automation_mod.AutomationHost, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(Request, allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const req = parsed.value;
    const op = req.operationName orelse inferOperation(req.query orelse "") orelse return error.UnknownOperation;

    if (std.mem.eql(u8, op, "sessions")) {
        var result = try host.execute(null, .list_sessions);
        defer result.deinit(allocator);
        return resultEnvelopeAlloc(allocator, "sessions", &result);
    }
    if (std.mem.eql(u8, op, "primarySession")) {
        var result = try host.execute(null, .get_primary_session);
        defer result.deinit(allocator);
        return resultEnvelopeAlloc(allocator, "primarySession", &result);
    }
    if (std.mem.eql(u8, op, "capabilities")) {
        var result = try host.execute(req.session_id, .get_capabilities);
        defer result.deinit(allocator);
        return resultEnvelopeAlloc(allocator, "capabilities", &result);
    }
    if (std.mem.eql(u8, op, "replayEvents")) {
        var result = try host.execute(null, .replay_events);
        defer result.deinit(allocator);
        return resultEnvelopeAlloc(allocator, "replayEvents", &result);
    }
    if (std.mem.eql(u8, op, "createShellSession")) {
        const id = try host.createShellSession(.{});
        return std.fmt.allocPrint(allocator, "{{\"data\":{{\"createShellSession\":{{\"session_id\":{d}}}}}}}", .{id});
    }

    const session_id = req.session_id orelse return error.MissingSessionId;
    var result = try host.execute(session_id, mapOperation(op, req));
    defer result.deinit(allocator);
    return switch (result) {
        .text => |text| std.fmt.allocPrint(allocator, "{{\"data\":{{\"{s}\":\"{s}\"}}}}", .{ op, text }),
        .generation => |generation| std.fmt.allocPrint(allocator, "{{\"data\":{{\"{s}\":{{\"generation\":{d}}}}}}}", .{ op, generation }),
        .buffer, .shell_state, .metrics, .cursor, .process, .last_exit_code, .capabilities, .input_log, .command_history, .sessions, .events, .replay, .session_id, .none => resultEnvelopeAlloc(allocator, op, &result),
    };
}

fn inferOperation(query: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, query, "sessions") != null) return "sessions";
    if (std.mem.indexOf(u8, query, "primarySession") != null) return "primarySession";
    if (std.mem.indexOf(u8, query, "capabilities") != null) return "capabilities";
    if (std.mem.indexOf(u8, query, "replayEvents") != null) return "replayEvents";
    if (std.mem.indexOf(u8, query, "visibleText") != null) return "visibleText";
    if (std.mem.indexOf(u8, query, "scrollbackText") != null) return "scrollbackText";
    if (std.mem.indexOf(u8, query, "visibleBuffer") != null) return "visibleBuffer";
    if (std.mem.indexOf(u8, query, "scrollbackBuffer") != null) return "scrollbackBuffer";
    if (std.mem.indexOf(u8, query, "metrics") != null) return "metrics";
    if (std.mem.indexOf(u8, query, "shellState") != null) return "shellState";
    if (std.mem.indexOf(u8, query, "cursor") != null) return "cursor";
    if (std.mem.indexOf(u8, query, "lastCommand") != null) return "lastCommand";
    if (std.mem.indexOf(u8, query, "lastExitCode") != null) return "lastExitCode";
    if (std.mem.indexOf(u8, query, "inputLog") != null) return "inputLog";
    if (std.mem.indexOf(u8, query, "commandHistory") != null) return "commandHistory";
    if (std.mem.indexOf(u8, query, "sendText") != null) return "sendText";
    if (std.mem.indexOf(u8, query, "invokeCommand") != null) return "invokeCommand";
    if (std.mem.indexOf(u8, query, "resizeTerminal") != null) return "resizeTerminal";
    if (std.mem.indexOf(u8, query, "saveScreenshotPng") != null) return "saveScreenshotPng";
    return null;
}

fn mapOperation(op: []const u8, req: Request) automation_mod.Command {
    if (std.mem.eql(u8, op, "visibleText")) return .get_visible_text;
    if (std.mem.eql(u8, op, "visibleBuffer")) return .get_visible_buffer;
    if (std.mem.eql(u8, op, "primarySession")) return .get_primary_session;
    if (std.mem.eql(u8, op, "capabilities")) return .get_capabilities;
    if (std.mem.eql(u8, op, "scrollbackText")) return .get_scrollback_text;
    if (std.mem.eql(u8, op, "scrollbackBuffer")) return .get_scrollback_buffer;
    if (std.mem.eql(u8, op, "metrics")) return .get_metrics;
    if (std.mem.eql(u8, op, "shellState")) return .get_shell_state;
    if (std.mem.eql(u8, op, "cursor")) return .get_cursor;
    if (std.mem.eql(u8, op, "title")) return .get_title;
    if (std.mem.eql(u8, op, "cwd")) return .get_cwd;
    if (std.mem.eql(u8, op, "process")) return .get_process;
    if (std.mem.eql(u8, op, "lastCommand")) return .get_last_command;
    if (std.mem.eql(u8, op, "lastExitCode")) return .get_last_exit_code;
    if (std.mem.eql(u8, op, "inputLog")) return .get_input_log;
    if (std.mem.eql(u8, op, "commandHistory")) return .get_command_history;
    if (std.mem.eql(u8, op, "toggleFullscreen")) return .toggle_fullscreen;
    if (std.mem.eql(u8, op, "toggleZen")) return .toggle_zen;
    if (std.mem.eql(u8, op, "copyScreenshotClipboard")) return .copy_screenshot_clipboard;
    if (std.mem.eql(u8, op, "sendText")) return .{ .send_text = req.text orelse "" };
    if (std.mem.eql(u8, op, "invokeCommand")) return .{ .invoke_command = req.text orelse "" };
    if (std.mem.eql(u8, op, "sendCtrl")) return .{ .send_ctrl = req.ctrl orelse 0 };
    if (std.mem.eql(u8, op, "resizeTerminal")) return .{ .resize_terminal = .{ .rows = req.rows orelse 24, .cols = req.cols orelse 80 } };
    if (std.mem.eql(u8, op, "setWindowRect")) return .{ .set_window_rect = .{ .x = req.x, .y = req.y, .width = req.width, .height = req.height } };
    if (std.mem.eql(u8, op, "saveScreenshotPng")) return .{ .save_screenshot_png = req.path orelse "fmus-automation-shot.png" };
    if (std.mem.eql(u8, op, "pollEvents")) return .{ .poll_events = req.since_generation orelse 0 };
    if (std.mem.eql(u8, op, "replayEvents")) return .replay_events;
    return .get_visible_text;
}

fn resultEnvelopeAlloc(allocator: std.mem.Allocator, field_name: []const u8, result: *automation_mod.Result) ![]u8 {
    switch (result.*) {
        .none => return std.fmt.allocPrint(allocator, "{{\"data\":{{\"{s}\":true}}}}", .{field_name}),
        .session_id => |value| return std.fmt.allocPrint(allocator, "{{\"data\":{{\"{s}\":{{\"session_id\":{d}}}}}}}", .{ field_name, value }),
        .generation => |value| return std.fmt.allocPrint(allocator, "{{\"data\":{{\"{s}\":{{\"generation\":{d}}}}}}}", .{ field_name, value }),
        .text => |value| return std.fmt.allocPrint(allocator, "{{\"data\":{{\"{s}\":\"{s}\"}}}}", .{ field_name, value }),
        else => return std.fmt.allocPrint(allocator, "{{\"data\":{{\"{s}\":\"ok\"}}}}", .{field_name}),
    }
}

test "automation graphql sessions query works" {
    var host = automation_mod.AutomationHost.init(std.testing.allocator, .{});
    defer host.deinit();

    var runtime = try @import("runtime.zig").Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    _ = try host.attachRuntime(&runtime);

    const out = try handleJsonAlloc(&host, std.testing.allocator, "{ \"operationName\": \"sessions\" }");
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"data\"") != null);
}

test "automation graphql capabilities query works" {
    var host = automation_mod.AutomationHost.init(std.testing.allocator, .{});
    defer host.deinit();

    var runtime = try @import("runtime.zig").Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    _ = try host.attachRuntime(&runtime);

    const out = try handleJsonAlloc(&host, std.testing.allocator, "{ \"operationName\": \"capabilities\", \"session_id\": 1 }");
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"data\"") != null);
}
