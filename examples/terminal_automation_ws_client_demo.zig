const std = @import("std");
const fmus = @import("fmus");

const ReqCreate = struct {
    id: u64,
    method: []const u8,
    cwd: ?[]const u8 = null,
    title: ?[]const u8 = null,
    rows: ?usize = null,
    cols: ?usize = null,
    width: ?i32 = null,
    height: ?i32 = null,
};

const ReqBase = struct {
    id: u64,
    method: []const u8,
    session_id: ?u64 = null,
    text: ?[]const u8 = null,
    path: ?[]const u8 = null,
    since_generation: ?u64 = null,
};

const CreateResponse = struct {
    ok: bool,
    result: struct {
        id: u64,
        session_id: u64,
    },
};

fn sendJsonRequest(allocator: std.mem.Allocator, client: *fmus.ws.Client, value: anytype) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    try std.json.Stringify.value(value, .{}, &writer.writer);
    try client.sendText(writer.written());

    var scratch: [64 * 1024]u8 = undefined;
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    var client = try fmus.ws.Client.connect(allocator, prng.random(), "ws://127.0.0.1:9311", .{
        .protocol = "fmus.automation.v1",
    });
    defer client.deinit();

    const create_response_text = try sendJsonRequest(allocator, &client, ReqCreate{
        .id = 1,
        .method = "create_shell_session",
        .cwd = "C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig",
        .title = "FMUS Automation Demo",
        .rows = 30,
        .cols = 100,
        .width = 1200,
        .height = 800,
    });
    defer allocator.free(create_response_text);

    var create_parsed = try std.json.parseFromSlice(CreateResponse, allocator, create_response_text, .{
        .ignore_unknown_fields = true,
    });
    defer create_parsed.deinit();
    const session_id = create_parsed.value.result.session_id;

    const requests = [_]ReqBase{
        .{ .id = 2, .method = "send_text", .session_id = session_id, .text = "echo hello from automation\r" },
        .{ .id = 3, .method = "send_text", .session_id = session_id, .text = "dir\r" },
        .{ .id = 4, .method = "get_scrollback_text", .session_id = session_id },
        .{ .id = 5, .method = "get_capabilities", .session_id = session_id },
        .{ .id = 6, .method = "poll_events", .session_id = session_id, .since_generation = 0 },
    };

    const stdout = std.fs.File.stdout();
    for (requests) |req| {
        if (req.id == 4 or req.id == 5 or req.id == 6) {
            std.Thread.sleep(800 * std.time.ns_per_ms);
        }
        const response = try sendJsonRequest(allocator, &client, req);
        defer allocator.free(response);
        try stdout.writeAll(response);
        try stdout.writeAll("\n\n");
        std.Thread.sleep(250 * std.time.ns_per_ms);
    }

    try client.close(.normal, "done");
}
