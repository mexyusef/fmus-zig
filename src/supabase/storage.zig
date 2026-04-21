const std = @import("std");
const root = @import("root");
const http = if (@hasDecl(root, "http")) root.http else @import("../http.zig");
const config_mod = @import("config.zig");
const errors = @import("errors.zig");

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

    pub fn fromBucket(self: Client, bucket: []const u8) Bucket {
        return .{
            .allocator = self.allocator,
            .config = self.config,
            .bucket = bucket,
            .access_token = self.access_token,
        };
    }

    pub fn listBuckets(self: Client) !http.Response {
        const base = try self.config.storageUrlAlloc(self.allocator);
        defer self.allocator.free(base);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/bucket", .{base});
        defer self.allocator.free(url);

        var header_store = http.OwnedHeaders.init(self.allocator);
        defer header_store.deinit();
        try header_store.appendApiKey(self.config.api_key);
        try header_store.append("accept-encoding", "identity");
        try header_store.appendBearer(self.access_token orelse self.config.api_key);

        var response = try http.get(url).header(header_store.slice()).send(self.allocator);
        if (!response.ok()) {
            response.deinit();
            return errors.Error.StorageFailed;
        }
        return response;
    }
};

pub const Bucket = struct {
    allocator: std.mem.Allocator,
    config: config_mod.Config,
    bucket: []const u8,
    access_token: ?[]const u8 = null,

    pub fn upload(self: Bucket, path: []const u8, data: []const u8, content_type: []const u8) !http.Response {
        var request = try self.objectRequest(.post, path);
        defer request.deinit();
        return try request.request.body(data, content_type).send(self.allocator);
    }

    pub fn download(self: Bucket, path: []const u8) !http.Response {
        var request = try self.objectRequest(.get, path);
        defer request.deinit();
        return try request.request.send(self.allocator);
    }

    pub fn remove(self: Bucket, path: []const u8) !http.Response {
        var request = try self.objectRequest(.delete, path);
        defer request.deinit();
        return try request.request.send(self.allocator);
    }

    pub fn list(self: Bucket, prefix: ?[]const u8) !http.Response {
        const base = try self.baseUrlAlloc();
        defer self.allocator.free(base);

        const url = if (prefix) |value|
            try std.fmt.allocPrint(self.allocator, "{s}/object/list/{s}?prefix={s}", .{ base, self.bucket, value })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/object/list/{s}", .{ base, self.bucket });
        defer self.allocator.free(url);

        var header_store = try self.buildHeaders();
        defer header_store.deinit();
        var response = try http.get(url).header(header_store.slice()).send(self.allocator);
        if (!response.ok()) {
            response.deinit();
            return errors.Error.StorageFailed;
        }
        return response;
    }

    pub fn move(self: Bucket, from_path: []const u8, to_path: []const u8) !http.Response {
        return try self.objectAction("move", .{ .bucketId = self.bucket, .sourceKey = from_path, .destinationKey = to_path });
    }

    pub fn copy(self: Bucket, from_path: []const u8, to_path: []const u8) !http.Response {
        return try self.objectAction("copy", .{ .bucketId = self.bucket, .sourceKey = from_path, .destinationKey = to_path });
    }

    pub fn objectUrlAlloc(self: Bucket, path: []const u8) ![]u8 {
        const base = try self.baseUrlAlloc();
        defer self.allocator.free(base);
        return try std.fmt.allocPrint(self.allocator, "{s}/object/{s}/{s}", .{ base, self.bucket, path });
    }

    fn objectRequest(self: Bucket, method: http.Method, path: []const u8) !OwnedRequest {
        const url = try self.objectUrlAlloc(path);
        errdefer self.allocator.free(url);
        var header_store = try self.buildHeaders();
        errdefer header_store.deinit();
        return .{
            .allocator = self.allocator,
            .url = url,
            .headers = header_store,
            .request = .{ .method = method, .url = url, .headers = header_store.slice() },
        };
    }

    fn objectAction(self: Bucket, suffix: []const u8, payload: anytype) !http.Response {
        const base = try self.baseUrlAlloc();
        defer self.allocator.free(base);
        const url = try std.fmt.allocPrint(self.allocator, "{s}/object/{s}", .{ base, suffix });
        defer self.allocator.free(url);
        const body = try (if (@hasDecl(root, "json")) root.json else @import("../json.zig")).stringifyAlloc(self.allocator, payload);
        defer self.allocator.free(body);
        var header_store = try self.buildHeaders();
        defer header_store.deinit();
        var response = try http.post(url).header(header_store.slice()).body(body, "application/json").send(self.allocator);
        if (!response.ok()) {
            response.deinit();
            return errors.Error.StorageFailed;
        }
        return response;
    }

    fn buildHeaders(self: Bucket) !http.OwnedHeaders {
        var out = http.OwnedHeaders.init(self.allocator);
        errdefer out.deinit();
        try out.appendApiKey(self.config.api_key);
        try out.append("accept-encoding", "identity");
        try out.appendBearer(self.access_token orelse self.config.api_key);
        return out;
    }

    fn baseUrlAlloc(self: Bucket) ![]u8 {
        return try self.config.storageUrlAlloc(self.allocator);
    }
};

pub const OwnedRequest = struct {
    allocator: std.mem.Allocator,
    url: []u8,
    headers: http.OwnedHeaders,
    request: http.Request,

    pub fn deinit(self: *OwnedRequest) void {
        self.allocator.free(self.url);
        self.headers.deinit();
    }
};

test "storage bucket builds object url" {
    const client = Client.init(std.testing.allocator, config_mod.Config.init("https://demo.supabase.co", "anon"));
    const bucket = client.fromBucket("avatars");
    const url = try bucket.objectUrlAlloc("a.png");
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings("https://demo.supabase.co/storage/v1/object/avatars/a.png", url);
}
