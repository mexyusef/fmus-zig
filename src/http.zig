const std = @import("std");
const json = @import("json.zig");

pub const Method = enum {
    get,
    post,
    put,
    delete,

    fn toStd(self: Method) std.http.Method {
        return switch (self) {
            .get => .GET,
            .post => .POST,
            .put => .PUT,
            .delete => .DELETE,
        };
    }
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Response = struct {
    allocator: std.mem.Allocator,
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
    }

    pub fn text(self: *const Response) []const u8 {
        return self.body;
    }

    pub fn jsonParse(self: *const Response, comptime T: type) !T {
        return try json.parse(self.allocator, T, self.body);
    }
};

pub const Request = struct {
    method: Method,
    url: []const u8,
    headers: []const Header = &.{},
    body_data: ?[]const u8 = null,
    content_type: ?[]const u8 = null,

    pub fn header(self: Request, headers: []const Header) Request {
        var next = self;
        next.headers = headers;
        return next;
    }

    pub fn body(self: Request, data: []const u8, content_type: []const u8) Request {
        var next = self;
        next.body_data = data;
        next.content_type = content_type;
        return next;
    }

    pub fn send(self: Request, allocator: std.mem.Allocator) !Response {
        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(self.url);

        var extra_headers = std.ArrayList(std.http.Header).empty;
        defer extra_headers.deinit(allocator);
        for (self.headers) |h| {
            try extra_headers.append(allocator, .{ .name = h.name, .value = h.value });
        }

        var request = try client.request(self.method.toStd(), uri, .{
            .headers = .{
                .content_type = if (self.content_type) |ct| .{ .override = ct } else .omit,
            },
            .extra_headers = extra_headers.items,
        });
        defer request.deinit();

        if (self.body_data) |body_data| {
            request.transfer_encoding = .{ .content_length = body_data.len };
            var body_writer = try request.sendBodyUnflushed(&.{});
            try body_writer.writer.writeAll(body_data);
            try body_writer.end();
            try request.connection.?.flush();
        } else {
            var body_writer = try request.sendBodyUnflushed(&.{});
            try body_writer.end();
            try request.connection.?.flush();
        }

        var response = try request.receiveHead(&.{});
        var transfer_buffer: [16 * 1024]u8 = undefined;
        var reader = response.reader(&transfer_buffer);
        var writer: std.Io.Writer.Allocating = .init(allocator);
        defer writer.deinit();
        _ = reader.streamRemaining(&writer.writer) catch 0;
        return .{
            .allocator = allocator,
            .status = response.head.status,
            .body = try allocator.dupe(u8, writer.written()),
        };
    }

    pub fn text(self: Request, allocator: std.mem.Allocator) ![]u8 {
        var response = try self.send(allocator);
        errdefer response.deinit();
        const out = response.body;
        response.body = &.{};
        return out;
    }

    pub fn jsonParse(self: Request, allocator: std.mem.Allocator, comptime T: type) !T {
        var response = try self.send(allocator);
        defer response.deinit();
        return try response.jsonParse(T);
    }
};

pub fn get(url: []const u8) Request {
    return .{ .method = .get, .url = url };
}

pub fn post(url: []const u8) Request {
    return .{ .method = .post, .url = url };
}

pub fn put(url: []const u8) Request {
    return .{ .method = .put, .url = url };
}

pub fn del(url: []const u8) Request {
    return .{ .method = .delete, .url = url };
}

test "get creates request" {
    const req = get("https://example.com");
    try std.testing.expectEqual(Method.get, req.method);
}
