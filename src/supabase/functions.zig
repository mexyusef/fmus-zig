const std = @import("std");
const root = @import("root");
const http = if (@hasDecl(root, "http")) root.http else @import("../http.zig");
const json = if (@hasDecl(root, "json")) root.json else @import("../json.zig");
const config_mod = @import("config.zig");
const errors = @import("errors.zig");

pub const InvokeOptions = struct {
    method: http.Method = .post,
    content_type: []const u8 = "application/json",
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    config: config_mod.Config,
    access_token: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, config: config_mod.Config) Client {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn withAccessToken(self: Client, access_token: []const u8) Client {
        var next = self;
        next.access_token = access_token;
        return next;
    }

    pub fn invoke(self: Client, function_name: []const u8, payload: anytype, options: InvokeOptions) !http.Response {
        var request = try self.buildRequest(function_name, payload, options);
        defer request.deinit();

        var response = try request.request.send(self.allocator);
        if (!response.ok()) {
            response.deinit();
            return errors.Error.FunctionsFailed;
        }
        return response;
    }

    pub fn buildRequest(self: Client, function_name: []const u8, payload: anytype, options: InvokeOptions) !OwnedRequest {
        const base = try self.config.functionsUrlAlloc(self.allocator);
        defer self.allocator.free(base);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ base, function_name });
        errdefer self.allocator.free(url);

        const body = if (options.method == .get or options.method == .head)
            try self.allocator.alloc(u8, 0)
        else
            try json.stringifyAlloc(self.allocator, payload);
        errdefer self.allocator.free(body);

        var headers = http.OwnedHeaders.init(self.allocator);
        errdefer headers.deinit();
        try headers.appendApiKey(self.config.api_key);
        try headers.append("accept", "application/json");
        try headers.appendBearer(self.access_token orelse self.config.api_key);

        const base_request = http.Request{ .method = options.method, .url = url, .headers = headers.slice() };
        const request = if (options.method == .get or options.method == .head)
            base_request
        else
            base_request.body(body, options.content_type);

        return .{
            .allocator = self.allocator,
            .url = url,
            .body = body,
            .headers = headers,
            .request = request,
        };
    }
};

pub const OwnedRequest = struct {
    allocator: std.mem.Allocator,
    url: []u8,
    body: []u8,
    headers: http.OwnedHeaders,
    request: http.Request,

    pub fn deinit(self: *OwnedRequest) void {
        self.allocator.free(self.url);
        self.allocator.free(self.body);
        self.headers.deinit();
    }
};

test "functions request builds invoke url" {
    const client = Client.init(std.testing.allocator, config_mod.Config.init("https://demo.supabase.co", "anon"));
    var request = try client.buildRequest("hello", .{ .name = "zig" }, .{});
    defer request.deinit();

    try std.testing.expectEqualStrings("https://demo.supabase.co/functions/v1/hello", request.url);
    try std.testing.expect(std.mem.indexOf(u8, request.body, "\"zig\"") != null);
}
