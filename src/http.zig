const std = @import("std");
const json = @import("json.zig");

pub const Method = enum {
    get,
    post,
    put,
    patch,
    delete,
    head,
    options,

    fn toStd(self: Method) std.http.Method {
        return switch (self) {
            .get => .GET,
            .post => .POST,
            .put => .PUT,
            .patch => .PATCH,
            .delete => .DELETE,
            .head => .HEAD,
            .options => .OPTIONS,
        };
    }
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const QueryParam = struct {
    name: []const u8,
    value: []const u8,
};

pub const Response = struct {
    allocator: std.mem.Allocator,
    status: std.http.Status,
    headers: []Header,
    body: []u8,

    pub fn deinit(self: *Response) void {
        for (self.headers) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.value);
        }
        self.allocator.free(self.headers);
        self.allocator.free(self.body);
    }

    pub fn text(self: *const Response) []const u8 {
        return self.body;
    }

    pub fn statusCode(self: *const Response) u16 {
        return @intFromEnum(self.status);
    }

    pub fn ok(self: *const Response) bool {
        return self.status.class() == .success;
    }

    pub fn header(self: *const Response, name: []const u8) ?[]const u8 {
        for (self.headers) |item| {
            if (std.ascii.eqlIgnoreCase(item.name, name)) return item.value;
        }
        return null;
    }

    pub fn jsonParse(self: *const Response, comptime T: type) !T {
        return try json.parse(self.allocator, T, self.body);
    }

    pub fn failure(self: *const Response) ?FailureView {
        if (self.ok()) return null;
        return .{
            .status = self.status,
            .headers = self.headers,
            .body = self.body,
        };
    }
};

pub const FailureView = struct {
    status: std.http.Status,
    headers: []const Header,
    body: []const u8,

    pub fn statusCode(self: FailureView) u16 {
        return @intFromEnum(self.status);
    }

    pub fn header(self: FailureView, name: []const u8) ?[]const u8 {
        for (self.headers) |item| {
            if (std.ascii.eqlIgnoreCase(item.name, name)) return item.value;
        }
        return null;
    }

    pub fn jsonParse(self: FailureView, allocator: std.mem.Allocator, comptime T: type) !T {
        return try json.parse(allocator, T, self.body);
    }
};

pub const OwnedHeaders = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Header) = .empty,

    pub fn init(allocator: std.mem.Allocator) OwnedHeaders {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *OwnedHeaders) void {
        for (self.list.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.list.deinit(self.allocator);
    }

    pub fn append(self: *OwnedHeaders, name: []const u8, value: []const u8) !void {
        try self.list.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    pub fn appendApiKey(self: *OwnedHeaders, api_key: []const u8) !void {
        try self.append("apikey", api_key);
    }

    pub fn appendBearer(self: *OwnedHeaders, token: []const u8) !void {
        const value = try bearerTokenAlloc(self.allocator, token);
        errdefer self.allocator.free(value);
        try self.list.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, "Authorization"),
            .value = value,
        });
    }

    pub fn slice(self: *const OwnedHeaders) []const Header {
        return self.list.items;
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

    pub fn jsonBody(self: Request, allocator: std.mem.Allocator, value: anytype) !OwnedBody {
        const encoded = try json.stringifyAlloc(allocator, value);
        return .{
            .allocator = allocator,
            .request = self.body(encoded, "application/json"),
            .body = encoded,
        };
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
            try request.sendBodiless();
        }

        var response = try request.receiveHead(&.{});

        var header_list = std.ArrayList(Header).empty;
        defer {
            for (header_list.items) |item| {
                allocator.free(item.name);
                allocator.free(item.value);
            }
            header_list.deinit(allocator);
        }

        var header_it = response.head.iterateHeaders();
        while (header_it.next()) |item| {
            try header_list.append(allocator, .{
                .name = try allocator.dupe(u8, item.name),
                .value = try allocator.dupe(u8, item.value),
            });
        }

        const decompress_buffer: []u8 = switch (response.head.content_encoding) {
            .identity => &.{},
            .zstd => try allocator.alloc(u8, std.compress.zstd.default_window_len),
            .deflate, .gzip => try allocator.alloc(u8, std.compress.flate.max_window_len),
            .compress => return error.UnsupportedCompressionMethod,
        };
        defer if (response.head.content_encoding != .identity) allocator.free(decompress_buffer);

        var transfer_buffer: [16 * 1024]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
        var writer: std.Io.Writer.Allocating = .init(allocator);
        defer writer.deinit();
        _ = reader.streamRemaining(&writer.writer) catch 0;

        const response_body = try allocator.dupe(u8, writer.written());
        const headers = try header_list.toOwnedSlice(allocator);

        return .{
            .allocator = allocator,
            .status = response.head.status,
            .headers = headers,
            .body = response_body,
        };
    }

    pub fn text(self: Request, allocator: std.mem.Allocator) ![]u8 {
        var response = try self.send(allocator);
        defer {
            for (response.headers) |item| {
                allocator.free(item.name);
                allocator.free(item.value);
            }
            allocator.free(response.headers);
        }
        const out = response.body;
        response.body = try allocator.alloc(u8, 0);
        return out;
    }

    pub fn jsonParse(self: Request, allocator: std.mem.Allocator, comptime T: type) !T {
        var response = try self.send(allocator);
        defer response.deinit();
        return try response.jsonParse(T);
    }
};

pub const OwnedBody = struct {
    allocator: std.mem.Allocator,
    request: Request,
    body: []u8,

    pub fn deinit(self: *OwnedBody) void {
        self.allocator.free(self.body);
    }
};

pub fn urlWithQueryAlloc(allocator: std.mem.Allocator, url: []const u8, params: []const QueryParam) ![]u8 {
    if (params.len == 0) return allocator.dupe(u8, url);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, url);
    try out.append(allocator, if (std.mem.indexOfScalar(u8, url, '?') == null) '?' else '&');

    for (params, 0..) |param, idx| {
        if (idx > 0) try out.append(allocator, '&');

        const encoded_name = try encodeQueryComponentAlloc(allocator, param.name);
        defer allocator.free(encoded_name);
        const encoded_value = try encodeQueryComponentAlloc(allocator, param.value);
        defer allocator.free(encoded_value);

        try out.appendSlice(allocator, encoded_name);
        try out.append(allocator, '=');
        try out.appendSlice(allocator, encoded_value);
    }

    return out.toOwnedSlice(allocator);
}

pub fn bearerTokenAlloc(allocator: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
}

pub fn jsonBodyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try json.stringifyAlloc(allocator, value);
}

fn encodeQueryComponentAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{f}",
        .{std.fmt.alt(std.Uri.Component{ .raw = input }, .formatQuery)},
    );
}

pub fn get(url: []const u8) Request {
    return .{ .method = .get, .url = url };
}

pub fn post(url: []const u8) Request {
    return .{ .method = .post, .url = url };
}

pub fn put(url: []const u8) Request {
    return .{ .method = .put, .url = url };
}

pub fn patch(url: []const u8) Request {
    return .{ .method = .patch, .url = url };
}

pub fn del(url: []const u8) Request {
    return .{ .method = .delete, .url = url };
}

pub fn head(url: []const u8) Request {
    return .{ .method = .head, .url = url };
}

pub fn options(url: []const u8) Request {
    return .{ .method = .options, .url = url };
}

test "get creates request" {
    const req = get("https://example.com");
    try std.testing.expectEqual(Method.get, req.method);
}

test "url with query alloc encodes params" {
    const alloc = std.testing.allocator;
    const out = try urlWithQueryAlloc(alloc, "https://example.com/rest/v1/todos", &.{
        .{ .name = "select", .value = "id,name" },
        .{ .name = "user name", .value = "zig zig" },
    });
    defer alloc.free(out);

    try std.testing.expectEqualStrings(
        "https://example.com/rest/v1/todos?select=id,name&user%20name=zig%20zig",
        out,
    );
}

test "owned headers appends auth helpers" {
    var headers = OwnedHeaders.init(std.testing.allocator);
    defer headers.deinit();

    try headers.appendApiKey("anon");
    try headers.appendBearer("token-123");

    try std.testing.expectEqual(@as(usize, 2), headers.slice().len);
    try std.testing.expectEqualStrings("apikey", headers.slice()[0].name);
    try std.testing.expectEqualStrings("Bearer token-123", headers.slice()[1].value);
}

test "response failure view exposes status and body" {
    const alloc = std.testing.allocator;
    var response = Response{
        .allocator = alloc,
        .status = .bad_request,
        .headers = try alloc.dupe(Header, &.{
            .{ .name = try alloc.dupe(u8, "content-type"), .value = try alloc.dupe(u8, "application/json") },
        }),
        .body = try alloc.dupe(u8, "{\"message\":\"bad\"}"),
    };
    defer response.deinit();

    const failure = response.failure().?;
    try std.testing.expectEqual(@as(u16, 400), failure.statusCode());
    try std.testing.expectEqualStrings("application/json", failure.header("Content-Type").?);
}

test "head request stays bodyless" {
    const req = head("https://example.com");
    try std.testing.expectEqual(Method.head, req.method);
    try std.testing.expect(req.body_data == null);
}
