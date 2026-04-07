const std = @import("std");
const fmus = @import("fmus");

const Request = struct {
    id: u64,
    method: []const u8,
    session_id: ?u64 = null,
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

const SessionInfo = struct {
    id: u64,
    title: []const u8,
    cwd: []const u8,
    attached: bool = false,
    owned: bool = false,
    primary: bool = false,
    visible: bool = false,
};

const SessionsResponse = struct {
    ok: bool,
    result: struct {
        id: u64 = 0,
        sessions: []SessionInfo,
    },
};

const PrimaryResponse = struct {
    ok: bool,
    result: struct {
        id: u64 = 0,
        session_id: u64,
    },
};

fn decodeEscapesAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
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

fn sendJsonRequest(allocator: std.mem.Allocator, client: *fmus.ws.Client, value: anytype) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    try std.json.Stringify.value(value, .{}, &writer.writer);
    try client.sendText(writer.written());
    var scratch: [128 * 1024]u8 = undefined;
    const msg = try client.receive(&scratch);
    return switch (msg) {
        .text => |text| text,
        .binary => |bytes| bytes,
        .close => |close_msg| {
            defer allocator.free(close_msg.reason);
            return error.ConnectionClosed;
        },
    };
}

fn connectUrlAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "FMUS_AUTOMATION_WS_URL")) |value| return value else |_| {}
    return allocator.dupe(u8, "ws://127.0.0.1:9311");
}

fn connectWithRetry(allocator: std.mem.Allocator, random: std.Random, ws_url: []const u8) !fmus.ws.Client {
    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        return fmus.ws.Client.connect(allocator, random, ws_url, .{ .protocol = "fmus.automation.v1" }) catch |err| switch (err) {
            error.ConnectionRefused => {
                if (attempt >= 19) return err;
                std.debug.print("waiting for visible automation server at {s} (attempt {d}/20)\n", .{ ws_url, attempt + 1 });
                std.Thread.sleep(500 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
    }
}

fn resolvePrimarySession(allocator: std.mem.Allocator, client: *fmus.ws.Client) !u64 {
    const primary_raw = try sendJsonRequest(allocator, client, Request{
        .id = 1,
        .method = "get_primary_session",
    });
    defer allocator.free(primary_raw);

    var primary = std.json.parseFromSlice(PrimaryResponse, allocator, primary_raw, .{ .ignore_unknown_fields = true }) catch null;
    if (primary) |*parsed| {
        defer parsed.deinit();
        if (parsed.value.ok) return parsed.value.result.session_id;
    }

    const sessions_raw = try sendJsonRequest(allocator, client, Request{
        .id = 2,
        .method = "list_sessions",
    });
    defer allocator.free(sessions_raw);
    var parsed_sessions = try std.json.parseFromSlice(SessionsResponse, allocator, sessions_raw, .{ .ignore_unknown_fields = true });
    defer parsed_sessions.deinit();
    for (parsed_sessions.value.result.sessions) |session| {
        if (session.primary or (session.visible and session.attached)) return session.id;
    }
    return error.NoPrimarySession;
}

fn printHelp() void {
    std.debug.print(
        \\visible terminal commands:
        \\  text <bytes>         sends to the visible session
        \\  ctrl <char>          send control character
        \\  esc <bytes>          send escape sequence
        \\  visible
        \\  scrollback
        \\  metrics
        \\  title
        \\  cwd
        \\  process
        \\  cap
        \\  events [since]
        \\  shot <path>
        \\  fullscreen
        \\  zen
        \\  resize <rows> <cols>
        \\  move <x> <y> <w> <h>
        \\  sessions
        \\  target
        \\  use <session_id>
        \\  replay
        \\  help
        \\  quit
        \\
    , .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ws_url = try connectUrlAlloc(allocator);
    defer allocator.free(ws_url);

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    var client = try connectWithRetry(allocator, prng.random(), ws_url);
    defer client.deinit();

    var next_id: u64 = 10;
    var current_session = try resolvePrimarySession(allocator, &client);
    std.debug.print("connected to {s}, target visible session {d}\n", .{ ws_url, current_session });
    printHelp();

    const stdin_reader = std.fs.File.stdin().deprecatedReader();
    const stdout = std.fs.File.stdout();
    while (true) {
        try stdout.writeAll("fmus-visible> ");
        const maybe_line = try stdin_reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096);
        const line = maybe_line orelse break;
        defer allocator.free(line);
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) break;
        if (std.mem.eql(u8, trimmed, "help")) {
            printHelp();
            continue;
        }

        var parts = std.mem.tokenizeScalar(u8, trimmed, ' ');
        const cmd = parts.next() orelse continue;
        var req = Request{ .id = next_id, .method = cmd, .session_id = current_session };
        next_id += 1;
        var decoded: ?[]u8 = null;
        defer if (decoded) |buf| allocator.free(buf);

        if (std.mem.eql(u8, cmd, "sessions")) {
            req.method = "list_sessions";
            req.session_id = null;
        } else if (std.mem.eql(u8, cmd, "target")) {
            std.debug.print("current target session {d}\n", .{current_session});
            continue;
        } else if (std.mem.eql(u8, cmd, "use")) {
            const id_text = parts.next() orelse {
                try stdout.writeAll("missing session id\n");
                continue;
            };
            current_session = try std.fmt.parseInt(u64, id_text, 10);
            std.debug.print("target session {d}\n", .{current_session});
            continue;
        } else if (std.mem.eql(u8, cmd, "text")) {
            req.method = "send_text";
            decoded = try decodeEscapesAlloc(allocator, trimmed[cmd.len + 1 ..]);
            req.text = decoded.?;
        } else if (std.mem.eql(u8, cmd, "ctrl")) {
            req.method = "send_ctrl";
            const arg = parts.next() orelse {
                try stdout.writeAll("missing ctrl char\n");
                continue;
            };
            req.ctrl = arg[0];
        } else if (std.mem.eql(u8, cmd, "esc")) {
            req.method = "send_escape";
            decoded = try decodeEscapesAlloc(allocator, trimmed[cmd.len + 1 ..]);
            req.text = decoded.?;
        } else if (std.mem.eql(u8, cmd, "visible")) req.method = "get_visible_text"
        else if (std.mem.eql(u8, cmd, "scrollback")) req.method = "get_scrollback_text"
        else if (std.mem.eql(u8, cmd, "metrics")) req.method = "get_metrics"
        else if (std.mem.eql(u8, cmd, "title")) req.method = "get_title"
        else if (std.mem.eql(u8, cmd, "cwd")) req.method = "get_cwd"
        else if (std.mem.eql(u8, cmd, "process")) req.method = "get_process"
        else if (std.mem.eql(u8, cmd, "cap")) req.method = "get_capabilities"
        else if (std.mem.eql(u8, cmd, "events")) {
            req.method = "poll_events";
            if (parts.next()) |since| req.since_generation = try std.fmt.parseInt(u64, since, 10) else req.since_generation = 0;
        } else if (std.mem.eql(u8, cmd, "shot")) {
            req.method = "save_screenshot_png";
            req.path = parts.next() orelse "visible-automation-shot.png";
        } else if (std.mem.eql(u8, cmd, "fullscreen")) req.method = "toggle_fullscreen"
        else if (std.mem.eql(u8, cmd, "zen")) req.method = "toggle_zen"
        else if (std.mem.eql(u8, cmd, "resize")) {
            req.method = "resize_terminal";
            req.rows = try std.fmt.parseInt(usize, parts.next() orelse return error.MissingRows, 10);
            req.cols = try std.fmt.parseInt(usize, parts.next() orelse return error.MissingCols, 10);
        } else if (std.mem.eql(u8, cmd, "move")) {
            req.method = "set_window_rect";
            req.x = try std.fmt.parseInt(i32, parts.next() orelse return error.MissingX, 10);
            req.y = try std.fmt.parseInt(i32, parts.next() orelse return error.MissingY, 10);
            req.width = try std.fmt.parseInt(i32, parts.next() orelse return error.MissingWidth, 10);
            req.height = try std.fmt.parseInt(i32, parts.next() orelse return error.MissingHeight, 10);
        } else if (std.mem.eql(u8, cmd, "replay")) {
            req.method = "replay_events";
            req.session_id = null;
        } else {
            try stdout.writeAll("unknown command\n");
            continue;
        }

        const response = try sendJsonRequest(allocator, &client, req);
        defer allocator.free(response);
        try stdout.writeAll(response);
        try stdout.writeAll("\n");
    }

    try client.close(.normal, "done");
}
