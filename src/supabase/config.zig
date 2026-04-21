const std = @import("std");
const env = @import("../env.zig");

pub const KeyMode = enum {
    anon,
    service,
};

pub const Config = struct {
    url: []const u8,
    api_key: []const u8,
    schema: []const u8 = "public",
    auth_storage_key: ?[]const u8 = null,
    service_key: ?[]const u8 = null,

    pub fn init(url: []const u8, api_key: []const u8) Config {
        return .{
            .url = url,
            .api_key = api_key,
        };
    }

    pub fn restUrlAlloc(self: Config, allocator: std.mem.Allocator) ![]u8 {
        return joinPathAlloc(allocator, self.url, "rest/v1");
    }

    pub fn authUrlAlloc(self: Config, allocator: std.mem.Allocator) ![]u8 {
        return joinPathAlloc(allocator, self.url, "auth/v1");
    }

    pub fn storageUrlAlloc(self: Config, allocator: std.mem.Allocator) ![]u8 {
        return joinPathAlloc(allocator, self.url, "storage/v1");
    }

    pub fn functionsUrlAlloc(self: Config, allocator: std.mem.Allocator) ![]u8 {
        return joinPathAlloc(allocator, self.url, "functions/v1");
    }

    pub fn realtimeUrlAlloc(self: Config, allocator: std.mem.Allocator) ![]u8 {
        const http_url = try joinPathAlloc(allocator, self.url, "realtime/v1");
        defer allocator.free(http_url);
        if (std.mem.startsWith(u8, http_url, "https://")) {
            return try std.fmt.allocPrint(allocator, "wss://{s}", .{http_url["https://".len..]});
        }
        if (std.mem.startsWith(u8, http_url, "http://")) {
            return try std.fmt.allocPrint(allocator, "ws://{s}", .{http_url["http://".len..]});
        }
        return error.InvalidSupabaseUrl;
    }

    pub fn defaultStorageKeyAlloc(self: Config, allocator: std.mem.Allocator) ![]u8 {
        const uri = try std.Uri.parse(self.url);
        const host = uri.host orelse return error.InvalidSupabaseUrl;
        const dot = std.mem.indexOfScalar(u8, host.percent_encoded, '.') orelse host.percent_encoded.len;
        return try std.fmt.allocPrint(allocator, "sb-{s}-auth-token", .{host.percent_encoded[0..dot]});
    }
};

pub const Loaded = struct {
    allocator: std.mem.Allocator,
    config: Config,
    owned_url: []u8,
    owned_anon_key: []u8,
    owned_api_key: []u8,
    owned_schema: ?[]u8 = null,
    owned_auth_storage_key: ?[]u8 = null,
    owned_service_key: ?[]u8 = null,

    pub fn deinit(self: *Loaded) void {
        self.allocator.free(self.owned_url);
        if (self.owned_anon_key.ptr != self.owned_api_key.ptr) self.allocator.free(self.owned_anon_key);
        self.allocator.free(self.owned_api_key);
        if (self.owned_schema) |value| self.allocator.free(value);
        if (self.owned_auth_storage_key) |value| self.allocator.free(value);
        if (self.owned_service_key) |value| {
            if (value.ptr != self.owned_api_key.ptr) self.allocator.free(value);
        }
    }
};

pub fn loadFromEnvFileOrProcess(allocator: std.mem.Allocator, dotenv_path: []const u8, mode: KeyMode) !Loaded {
    const url = (try env.getOrDotEnv(allocator, "SUPABASE_URL", dotenv_path)) orelse return error.MissingSupabaseUrl;
    errdefer allocator.free(url);

    const anon_key = (try env.getOrDotEnv(allocator, "SUPABASE_ANON_KEY", dotenv_path)) orelse return error.MissingSupabaseAnonKey;
    errdefer allocator.free(anon_key);

    const service_key = try env.getOrDotEnv(allocator, "SUPABASE_SERVICE_KEY", dotenv_path);
    errdefer if (service_key) |value| allocator.free(value);

    const schema = try env.getOrDotEnv(allocator, "SUPABASE_SCHEMA", dotenv_path);
    errdefer if (schema) |value| allocator.free(value);

    const auth_storage_key = try env.getOrDotEnv(allocator, "SUPABASE_AUTH_STORAGE_KEY", dotenv_path);
    errdefer if (auth_storage_key) |value| allocator.free(value);

    const api_key = switch (mode) {
        .anon => anon_key,
        .service => service_key orelse return error.MissingSupabaseServiceKey,
    };

    return .{
        .allocator = allocator,
        .config = .{
            .url = url,
            .api_key = api_key,
            .schema = schema orelse "public",
            .auth_storage_key = auth_storage_key,
            .service_key = service_key,
        },
        .owned_url = url,
        .owned_anon_key = anon_key,
        .owned_api_key = api_key,
        .owned_schema = schema,
        .owned_auth_storage_key = auth_storage_key,
        .owned_service_key = service_key,
    };
}

fn joinPathAlloc(allocator: std.mem.Allocator, base: []const u8, suffix: []const u8) ![]u8 {
    const trimmed = std.mem.trimRight(u8, base, "/");
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ trimmed, suffix });
}

test "config derives service urls" {
    const alloc = std.testing.allocator;
    const cfg = Config.init("https://demo.supabase.co/", "anon");

    const rest = try cfg.restUrlAlloc(alloc);
    defer alloc.free(rest);
    const realtime = try cfg.realtimeUrlAlloc(alloc);
    defer alloc.free(realtime);
    const storage_key = try cfg.defaultStorageKeyAlloc(alloc);
    defer alloc.free(storage_key);

    try std.testing.expectEqualStrings("https://demo.supabase.co/rest/v1", rest);
    try std.testing.expectEqualStrings("wss://demo.supabase.co/realtime/v1", realtime);
    try std.testing.expectEqualStrings("sb-demo-auth-token", storage_key);
}

test "config loads from dotenv file" {
    const path = "__fmus_supabase_env_test.env";
    defer @import("../fs.zig").remove(path) catch {};
    try @import("../fs.zig").writeText(path,
        \\SUPABASE_URL=https://demo.supabase.co
        \\SUPABASE_ANON_KEY=anon-key
        \\SUPABASE_SERVICE_KEY=service-key
        \\SUPABASE_SCHEMA=private
    );

    var loaded = try loadFromEnvFileOrProcess(std.testing.allocator, path, .service);
    defer loaded.deinit();

    try std.testing.expectEqualStrings("https://demo.supabase.co", loaded.config.url);
    try std.testing.expectEqualStrings("service-key", loaded.config.api_key);
    try std.testing.expectEqualStrings("private", loaded.config.schema);
    try std.testing.expectEqualStrings("service-key", loaded.config.service_key.?);
}
