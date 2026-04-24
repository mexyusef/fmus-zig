const std = @import("std");
const types = @import("types.zig");

pub const DispatchError = error{
    InvalidBatchResponseState,
};

pub const Handler = *const fn (
    allocator: std.mem.Allocator,
    ctx: ?*anyopaque,
    params: ?std.json.Value,
) anyerror![]u8;

pub const Router = struct {
    allocator: std.mem.Allocator,
    ctx: ?*anyopaque = null,
    methods: std.StringHashMap(Handler),

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .allocator = allocator,
            .methods = std.StringHashMap(Handler).init(allocator),
        };
    }

    pub fn deinit(self: *Router) void {
        self.methods.deinit();
    }

    pub fn add(self: *Router, method: []const u8, handler: Handler) !void {
        try self.methods.put(method, handler);
    }

    pub fn setContext(self: *Router, ctx: ?*anyopaque) void {
        self.ctx = ctx;
    }

    pub fn dispatchDocumentAlloc(self: *const Router, allocator: std.mem.Allocator, doc: *const types.Document) !?[]u8 {
        return switch (doc.root) {
            .single => |message| try self.dispatchSingleAlloc(allocator, message),
            .batch => |batch| try self.dispatchBatchAlloc(allocator, batch),
        };
    }

    fn dispatchBatchAlloc(self: *const Router, allocator: std.mem.Allocator, batch: []types.MessageView) !?[]u8 {
        var rendered = std.array_list.Managed([]u8).init(allocator);
        defer {
            for (rendered.items) |item| allocator.free(item);
            rendered.deinit();
        }

        for (batch) |message| {
            const response = try self.dispatchSingleAlloc(allocator, message);
            if (response) |response_json| {
                try rendered.append(response_json);
            }
        }

        if (rendered.items.len == 0) return null;

        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        try out.append('[');
        for (rendered.items, 0..) |item, idx| {
            if (idx != 0) try out.append(',');
            try out.appendSlice(item);
        }
        try out.append(']');
        return try out.toOwnedSlice();
    }

    fn dispatchSingleAlloc(self: *const Router, allocator: std.mem.Allocator, message: types.MessageView) !?[]u8 {
        return switch (message) {
            .request => |request| blk: {
                const handler = self.methods.get(request.method) orelse {
                    const message_json = try stringifyAlloc(allocator, "method not found");
                    defer allocator.free(message_json);
                    break :blk try types.errorJsonAlloc(
                        allocator,
                        request.id,
                        @intFromEnum(types.StandardErrorCode.method_not_found),
                        message_json,
                        null,
                    );
                };

                const result_json = handler(allocator, self.ctx, request.params) catch |err| {
                    const message_json = try stringifyAlloc(allocator, @errorName(err));
                    defer allocator.free(message_json);
                    break :blk try types.errorJsonAlloc(
                        allocator,
                        request.id,
                        @intFromEnum(types.StandardErrorCode.internal_error),
                        message_json,
                        null,
                    );
                };
                defer allocator.free(result_json);
                break :blk try types.resultJsonAlloc(allocator, request.id, result_json);
            },
            .notification => |notification| blk: {
                const handler = self.methods.get(notification.method) orelse break :blk null;
                const result_json = handler(allocator, self.ctx, notification.params) catch break :blk null;
                allocator.free(result_json);
                break :blk null;
            },
            .response => null,
        };
    }
};

test "router dispatches request and notification" {
    const allocator = std.testing.allocator;

    const TestCtx = struct {
        hit_count: usize = 0,
    };

    const state = struct {
        fn ping(allocator_inner: std.mem.Allocator, ctx: ?*anyopaque, _: ?std.json.Value) ![]u8 {
            const typed: *TestCtx = @ptrCast(@alignCast(ctx.?));
            typed.hit_count += 1;
            return stringifyAlloc(allocator_inner, .{ .pong = true });
        }
    };

    var ctx = TestCtx{};
    var r = Router.init(allocator);
    defer r.deinit();
    r.setContext(&ctx);
    try r.add("ping", state.ping);

    var request_doc = try types.parseMessageAlloc(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":1}");
    defer request_doc.deinit();
    const response = (try r.dispatchDocumentAlloc(allocator, &request_doc)).?;
    defer allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"pong\":true") != null);

    var notification_doc = try types.parseMessageAlloc(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}");
    defer notification_doc.deinit();
    try std.testing.expect((try r.dispatchDocumentAlloc(allocator, &notification_doc)) == null);
    try std.testing.expectEqual(@as(usize, 2), ctx.hit_count);
}

fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}
