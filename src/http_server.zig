const std = @import("std");
const socket = @import("socket.zig");

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    body: []const u8,
    raw: []const u8,
};

pub const Response = struct {
    status: u16 = 200,
    content_type: []const u8 = "application/json",
    body: []const u8,
};

pub fn readRequest(handle: std.net.Stream.Handle, buffer: []u8) !?Request {
    const size = try socket.recv(handle, buffer);
    if (size == 0) return null;

    const raw = buffer[0..size];
    var lines = std.mem.splitSequence(u8, raw, "\r\n");
    const request_line = lines.next() orelse return error.BadRequest;

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return error.BadRequest;
    const target = parts.next() orelse return error.BadRequest;

    var body: []const u8 = "";
    if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |idx| {
        body = raw[idx + 4 ..];
    }

    return .{
        .method = method,
        .target = target,
        .body = body,
        .raw = raw,
    };
}

pub fn writeResponse(handle: std.net.Stream.Handle, response: Response) !void {
    const reason = switch (response.status) {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        else => "OK",
    };
    const rendered = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
        .{ response.status, reason, response.content_type, response.body.len, response.body },
    );
    defer std.heap.page_allocator.free(rendered);
    try socket.sendAll(handle, rendered);
}

test "http server module compiles" {
    try std.testing.expect(true);
}
