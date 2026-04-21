const std = @import("std");
const functions = @import("functions.zig");
const realtime = @import("realtime.zig");
const config_mod = @import("config.zig");
const rest = @import("rest.zig");
const storage = @import("storage.zig");
const auth = @import("auth.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    config: config_mod.Config,
    auth: auth.Client,
    rest: rest.Client,
    storage: storage.Client,
    functions: functions.Client,
    realtime: realtime.Client,

    pub fn init(allocator: std.mem.Allocator, config: config_mod.Config) Client {
        return .{
            .allocator = allocator,
            .config = config,
            .auth = auth.Client.init(allocator, config),
            .rest = rest.Client.init(allocator, config),
            .storage = storage.Client.init(allocator, config),
            .functions = functions.Client.init(allocator, config),
            .realtime = realtime.Client.init(allocator, config),
        };
    }

    pub fn from(self: Client, relation: []const u8) !@import("query_builder.zig").Builder {
        return try self.rest.from(relation);
    }

    pub fn schema(self: Client, schema_name: []const u8) Client {
        var next = self;
        next.config.schema = schema_name;
        next.rest = next.rest.withSchema(schema_name);
        return next;
    }

    pub fn withAccessToken(self: Client, access_token: []const u8) Client {
        var next = self;
        next.rest = next.rest.withAccessToken(access_token);
        next.storage = next.storage.withAccessToken(access_token);
        next.functions = next.functions.withAccessToken(access_token);
        next.realtime = next.realtime.withAccessToken(access_token);
        return next;
    }
};

test "client wires derived service urls and schema" {
    const client = Client.init(std.testing.allocator, config_mod.Config.init("https://demo.supabase.co", "anon"));
    const scoped = client.schema("private");
    var builder = try scoped.from("todos");
    defer builder.deinit();

    const realtime_url = try client.config.realtimeUrlAlloc(std.testing.allocator);
    defer std.testing.allocator.free(realtime_url);

    const storage_url = try client.storage.fromBucket("avatars").objectUrlAlloc("a.png");
    defer std.testing.allocator.free(storage_url);

    var fn_request = try client.functions.buildRequest("hello", .{ .name = "zig" }, .{});
    defer fn_request.deinit();

    var memory_realtime = client.realtime;
    defer memory_realtime.deinit();
    const encoded_join = try @import("phoenix.zig").encodeAlloc(std.testing.allocator, "realtime:public:todos", "phx_join", .{}, "1", "1");
    defer std.testing.allocator.free(encoded_join);

    try std.testing.expectEqualStrings("private", builder.schema);
    try std.testing.expectEqualStrings("wss://demo.supabase.co/realtime/v1", realtime_url);
    try std.testing.expectEqualStrings("https://demo.supabase.co/storage/v1/object/avatars/a.png", storage_url);
    try std.testing.expectEqualStrings("https://demo.supabase.co/functions/v1/hello", fn_request.url);
    try std.testing.expect(std.mem.indexOf(u8, encoded_join, "\"phx_join\"") != null);
}
