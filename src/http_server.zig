const std = @import("std");
const socket = @import("socket.zig");

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    version: []const u8,
    headers: []const Header,
    body: []const u8,
    raw: []const u8,

    pub fn header(self: Request, name: []const u8) ?[]const u8 {
        for (self.headers) |item| {
            if (std.ascii.eqlIgnoreCase(item.name, name)) return item.value;
        }
        return null;
    }

    pub fn containsTokenHeader(self: Request, name: []const u8, token: []const u8) bool {
        const value = self.header(name) orelse return false;
        var it = std.mem.splitScalar(u8, value, ',');
        while (it.next()) |part| {
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, part, " \t"), token)) return true;
        }
        return false;
    }

    pub fn isWebSocketUpgrade(self: Request) bool {
        const upgrade = self.header("Upgrade") orelse return false;
        return std.ascii.eqlIgnoreCase(upgrade, "websocket") and self.containsTokenHeader("Connection", "Upgrade");
    }
};

pub const Response = struct {
    status: u16 = 200,
    content_type: []const u8 = "application/json",
    body: []const u8,
    extra_headers: []const Header = &.{},
};

pub const Handler = *const fn (request: Request, response: *Response) anyerror!void;

pub const Route = struct {
    method: []const u8,
    target: []const u8,
    handler: Handler,
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    routes: std.ArrayListUnmanaged(Route) = .empty,

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit(self.allocator);
    }

    pub fn addExact(self: *Router, method: []const u8, target: []const u8, handler: Handler) !void {
        try self.routes.append(self.allocator, .{
            .method = method,
            .target = target,
            .handler = handler,
        });
    }

    pub fn dispatch(self: *const Router, request: Request, response: *Response) !bool {
        for (self.routes.items) |route| {
            if (std.mem.eql(u8, request.method, route.method) and std.mem.eql(u8, request.target, route.target)) {
                try route.handler(request, response);
                return true;
            }
        }
        return false;
    }
};

pub fn readRequest(handle: std.net.Stream.Handle, buffer: []u8) !?Request {
    const size = try socket.recv(handle, buffer);
    if (size == 0) return null;
    return try parseRequestBytes(buffer[0..size]);
}

pub fn parseRequestBytes(raw: []const u8) !Request {
    var lines = std.mem.splitSequence(u8, raw, "\r\n");
    const request_line = lines.next() orelse return error.BadRequest;

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return error.BadRequest;
    const target = parts.next() orelse return error.BadRequest;
    const version = parts.next() orelse return error.BadRequest;

    var body: []const u8 = "";
    var header_count: usize = 0;
    var headers_storage: [32]Header = undefined;

    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (header_count == headers_storage.len) return error.TooManyHeaders;
        headers_storage[header_count] = .{
            .name = std.mem.trim(u8, line[0..colon], " \t"),
            .value = std.mem.trim(u8, line[colon + 1 ..], " \t"),
        };
        header_count += 1;
    }

    if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |idx| {
        body = raw[idx + 4 ..];
    }

    return Request{
        .method = method,
        .target = target,
        .version = version,
        .headers = headers_storage[0..header_count],
        .body = body,
        .raw = raw,
    };
}

pub fn writeResponse(handle: std.net.Stream.Handle, response: Response) !void {
    var rendered = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer rendered.deinit();
    const writer = rendered.writer();

    try writer.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n",
        .{ response.status, reasonPhrase(response.status), response.content_type, response.body.len },
    );
    for (response.extra_headers) |header| {
        try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
    }
    try writer.print("\r\n{s}", .{response.body});
    try socket.sendAll(handle, rendered.items);
}

fn reasonPhrase(status: u16) []const u8 {
    return switch (status) {
        101 => "Switching Protocols",
        200 => "OK",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        else => "OK",
    };
}

test "http server router dispatches exact route" {
    const allocator = std.testing.allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    const state = struct {
        fn health(_: Request, response: *Response) !void {
            response.status = 200;
            response.content_type = "text/plain";
            response.body = "ok";
        }
    };

    try router.addExact("GET", "/health", state.health);

    const raw =
        "GET /health HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "\r\n";
    var buffer: [128]u8 = undefined;
    @memcpy(buffer[0..raw.len], raw);
    const request = try parseRequestBytes(buffer[0..raw.len]);
    var response = Response{ .body = "" };
    try std.testing.expect(try router.dispatch(request, &response));
    try std.testing.expectEqual(@as(u16, 200), response.status);
    try std.testing.expectEqualStrings("ok", response.body);
}

test "http request detects websocket upgrade" {
    const raw =
        "GET /ws HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: keep-alive, Upgrade\r\n" ++
        "\r\n";
    var buffer: [256]u8 = undefined;
    @memcpy(buffer[0..raw.len], raw);
    const request = try parseRequestBytes(buffer[0..raw.len]);
    try std.testing.expect(request.isWebSocketUpgrade());
}
