const std = @import("std");

pub const StandardErrorCode = enum(i64) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,
};

pub const Id = union(enum) {
    null,
    string: []const u8,
    integer: i64,
};

pub const ErrorObject = struct {
    code: i64,
    message: []const u8,
    data: ?std.json.Value = null,
};

pub const RequestView = struct {
    id: Id,
    method: []const u8,
    params: ?std.json.Value = null,
};

pub const NotificationView = struct {
    method: []const u8,
    params: ?std.json.Value = null,
};

pub const ResponseView = struct {
    id: Id,
    result: ?std.json.Value = null,
    @"error": ?ErrorObject = null,
};

pub const MessageView = union(enum) {
    request: RequestView,
    notification: NotificationView,
    response: ResponseView,
};

pub const RootView = union(enum) {
    single: MessageView,
    batch: []MessageView,
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    parsed: std.json.Parsed(std.json.Value),
    root: RootView,

    pub fn deinit(self: *Document) void {
        switch (self.root) {
            .single => {},
            .batch => |batch| self.allocator.free(batch),
        }
        self.parsed.deinit();
    }
};

pub const ParseError = std.mem.Allocator.Error || error{
    InvalidJsonRpcVersion,
    InvalidMessage,
    InvalidBatch,
    MissingMethod,
    InvalidMethod,
    InvalidId,
    InvalidResponse,
    InvalidErrorObject,
};

pub fn parseMessageAlloc(allocator: std.mem.Allocator, input: []const u8) !Document {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    errdefer parsed.deinit();

    const root = try parseRoot(allocator, parsed.value);
    return .{
        .allocator = allocator,
        .parsed = parsed,
        .root = root,
    };
}

fn parseRoot(allocator: std.mem.Allocator, value: std.json.Value) ParseError!RootView {
    return switch (value) {
        .array => |array| blk: {
            if (array.items.len == 0) return ParseError.InvalidBatch;
            const batch = try allocator.alloc(MessageView, array.items.len);
            errdefer allocator.free(batch);
            for (array.items, 0..) |item, idx| {
                batch[idx] = try parseSingle(item);
            }
            break :blk .{ .batch = batch };
        },
        else => .{ .single = try parseSingle(value) },
    };
}

fn parseSingle(value: std.json.Value) ParseError!MessageView {
    const object = switch (value) {
        .object => |object| object,
        else => return ParseError.InvalidMessage,
    };

    const version = object.get("jsonrpc") orelse return ParseError.InvalidJsonRpcVersion;
    switch (version) {
        .string => |text| if (!std.mem.eql(u8, text, "2.0")) return ParseError.InvalidJsonRpcVersion,
        else => return ParseError.InvalidJsonRpcVersion,
    }

    if (object.get("method")) |method_value| {
        const method = switch (method_value) {
            .string => |text| text,
            else => return ParseError.InvalidMethod,
        };
        const params = object.get("params");
        if (object.get("id")) |id_value| {
            return .{
                .request = .{
                    .id = try parseId(id_value),
                    .method = method,
                    .params = params,
                },
            };
        }
        return .{
            .notification = .{
                .method = method,
                .params = params,
            },
        };
    }

    if (object.get("result") != null or object.get("error") != null) {
        const id_value = object.get("id") orelse return ParseError.InvalidResponse;
        const result = object.get("result");
        const error_value = object.get("error");
        if (result != null and error_value != null) return ParseError.InvalidResponse;
        if (result == null and error_value == null) return ParseError.InvalidResponse;

        return .{
            .response = .{
                .id = try parseId(id_value),
                .result = result,
                .@"error" = if (error_value) |raw| try parseErrorObject(raw) else null,
            },
        };
    }

    return ParseError.InvalidMessage;
}

fn parseId(value: std.json.Value) ParseError!Id {
    return switch (value) {
        .null => .null,
        .string => |text| .{ .string = text },
        .integer => |number| .{ .integer = number },
        else => ParseError.InvalidId,
    };
}

fn parseErrorObject(value: std.json.Value) ParseError!ErrorObject {
    const object = switch (value) {
        .object => |object| object,
        else => return ParseError.InvalidErrorObject,
    };

    const code_value = object.get("code") orelse return ParseError.InvalidErrorObject;
    const message_value = object.get("message") orelse return ParseError.InvalidErrorObject;
    const code = switch (code_value) {
        .integer => |number| number,
        else => return ParseError.InvalidErrorObject,
    };
    const message = switch (message_value) {
        .string => |text| text,
        else => return ParseError.InvalidErrorObject,
    };

    return .{
        .code = code,
        .message = message,
        .data = object.get("data"),
    };
}

pub fn requestAlloc(allocator: std.mem.Allocator, id: Id, method: []const u8, params: anytype) ![]u8 {
    const id_json = try idAlloc(allocator, id);
    defer allocator.free(id_json);
    const method_json = try stringifyAlloc(allocator, method);
    defer allocator.free(method_json);

    if (@TypeOf(params) == @TypeOf(null)) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"method\":{s}}}",
            .{ id_json, method_json },
        );
    }

    const params_json = try stringifyAlloc(allocator, params);
    defer allocator.free(params_json);
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"method\":{s},\"params\":{s}}}",
        .{ id_json, method_json, params_json },
    );
}

pub fn notificationAlloc(allocator: std.mem.Allocator, method: []const u8, params: anytype) ![]u8 {
    const method_json = try stringifyAlloc(allocator, method);
    defer allocator.free(method_json);

    if (@TypeOf(params) == @TypeOf(null)) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":{s}}}",
            .{method_json},
        );
    }

    const params_json = try stringifyAlloc(allocator, params);
    defer allocator.free(params_json);
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"method\":{s},\"params\":{s}}}",
        .{ method_json, params_json },
    );
}

pub fn resultAlloc(allocator: std.mem.Allocator, id: Id, result: anytype) ![]u8 {
    const result_json = try stringifyAlloc(allocator, result);
    defer allocator.free(result_json);
    return resultJsonAlloc(allocator, id, result_json);
}

pub fn resultJsonAlloc(allocator: std.mem.Allocator, id: Id, result_json: []const u8) ![]u8 {
    const id_json = try idAlloc(allocator, id);
    defer allocator.free(id_json);
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
        .{ id_json, result_json },
    );
}

pub fn errorAlloc(allocator: std.mem.Allocator, id: Id, rpc_error: ErrorObject) ![]u8 {
    const message_json = try stringifyAlloc(allocator, rpc_error.message);
    defer allocator.free(message_json);
    const data_json = if (rpc_error.data) |data| try stringifyAlloc(allocator, data) else null;
    defer if (data_json) |owned| allocator.free(owned);
    return errorJsonAlloc(allocator, id, rpc_error.code, message_json, data_json);
}

pub fn errorJsonAlloc(
    allocator: std.mem.Allocator,
    id: Id,
    code: i64,
    message_json: []const u8,
    data_json: ?[]const u8,
) ![]u8 {
    const id_json = try idAlloc(allocator, id);
    defer allocator.free(id_json);
    if (data_json) |data| {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":{s},\"data\":{s}}}}}",
            .{ id_json, code, message_json, data },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":{s}}}}}",
        .{ id_json, code, message_json },
    );
}

pub fn ok(allocator: std.mem.Allocator, id: []const u8, result: anytype) ![]u8 {
    return resultAlloc(allocator, .{ .string = id }, result);
}

fn idAlloc(allocator: std.mem.Allocator, id: Id) ![]u8 {
    switch (id) {
        .null => return allocator.dupe(u8, "null"),
        .string => |text| return stringifyAlloc(allocator, text),
        .integer => |number| return std.fmt.allocPrint(allocator, "{d}", .{number}),
    }
}

fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

test "parse request and response batch" {
    const allocator = std.testing.allocator;
    var doc = try parseMessageAlloc(
        allocator,
        \\[
        \\  {"jsonrpc":"2.0","method":"ping","id":1},
        \\  {"jsonrpc":"2.0","result":{"ok":true},"id":"2"}
        \\]
    );
    defer doc.deinit();

    switch (doc.root) {
        .batch => |batch| {
            try std.testing.expectEqual(@as(usize, 2), batch.len);
            try std.testing.expect(batch[0] == .request);
            try std.testing.expect(batch[1] == .response);
        },
        else => return error.UnexpectedRoot,
    }
}

test "compose jsonrpc ok response" {
    const allocator = std.testing.allocator;
    const out = try ok(allocator, "1", .{ .hello = "world" });
    defer allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"result\"") != null);
}
