const std = @import("std");
const root = @import("root");
const http = if (@hasDecl(root, "http")) root.http else @import("../http.zig");
const json = if (@hasDecl(root, "json")) root.json else @import("../json.zig");
const config_mod = @import("config.zig");
const errors = @import("errors.zig");
const query = @import("query_builder.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    config: config_mod.Config,
    access_token: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, config: config_mod.Config) Client {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn withAccessToken(self: Client, access_token: []const u8) Client {
        var next = self;
        next.access_token = access_token;
        return next;
    }

    pub fn withSchema(self: Client, schema: []const u8) Client {
        var next = self;
        next.config.schema = schema;
        return next;
    }

    pub fn from(self: Client, relation: []const u8) !query.Builder {
        const base_url = try self.config.restUrlAlloc(self.allocator);
        return query.Builder.initOwned(
            self.allocator,
            base_url,
            relation,
            self.config.api_key,
            self.config.schema,
            self.access_token,
        );
    }

    pub fn rpc(self: Client, function_name: []const u8, args: anytype) !http.Response {
        const base_url = try self.config.restUrlAlloc(self.allocator);
        defer self.allocator.free(base_url);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/rpc/{s}", .{ base_url, function_name });
        defer self.allocator.free(url);

        const body = try json.stringifyAlloc(self.allocator, args);
        defer self.allocator.free(body);

        var headers = http.OwnedHeaders.init(self.allocator);
        defer headers.deinit();
        try headers.appendApiKey(self.config.api_key);
        try headers.append("accept", "application/json");
        try headers.append("content-profile", self.config.schema);
        try headers.appendBearer(self.access_token orelse self.config.api_key);

        var response = try http.post(url).header(headers.slice()).body(body, "application/json").send(self.allocator);
        if (!response.ok()) {
            response.deinit();
            return errors.Error.QueryFailed;
        }
        return response;
    }

    pub fn rpcParse(self: Client, comptime T: type, function_name: []const u8, args: anytype) !T {
        var response = try self.rpc(function_name, args);
        defer response.deinit();
        return try response.jsonParse(T);
    }
};

test "rest client from uses configured schema" {
    const client = Client.init(std.testing.allocator, config_mod.Config{
        .url = "https://demo.supabase.co",
        .api_key = "anon",
        .schema = "custom",
    });
    var builder = try client.from("profiles");
    defer builder.deinit();

    try std.testing.expectEqualStrings("custom", builder.schema);
    try std.testing.expectEqualStrings("profiles", builder.relation);
}
