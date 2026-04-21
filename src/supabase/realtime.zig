const std = @import("std");
const root = @import("root");
const ws = if (@hasDecl(root, "ws")) root.ws else @import("../ws.zig");
const config_mod = @import("config.zig");
const phoenix = @import("phoenix.zig");

pub const Connection = union(enum) {
    disconnected,
    plain: ws.Client,
    secure: ws.SecureClient,

    pub fn deinit(self: *Connection) void {
        switch (self.*) {
            .disconnected => {},
            .plain => |*client| client.deinit(),
            .secure => |*client| client.deinit(),
        }
        self.* = .disconnected;
    }

    pub fn sendText(self: *Connection, text: []const u8) !void {
        return switch (self.*) {
            .disconnected => error.NotConnected,
            .plain => |*client| client.sendText(text),
            .secure => |*client| client.sendText(text),
        };
    }

    pub fn receive(self: *Connection, scratch: []u8) !ws.Message {
        return switch (self.*) {
            .disconnected => error.NotConnected,
            .plain => |*client| client.receive(scratch),
            .secure => |*client| client.receive(scratch),
        };
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    config: config_mod.Config,
    access_token: ?[]const u8 = null,
    connection: Connection = .disconnected,
    next_ref: usize = 1,

    pub fn init(allocator: std.mem.Allocator, config: config_mod.Config) Client {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn deinit(self: *Client) void {
        self.connection.deinit();
    }

    pub fn withAccessToken(self: Client, access_token: []const u8) Client {
        var next = self;
        next.access_token = access_token;
        return next;
    }

    pub fn connect(self: *Client, random: std.Random) !void {
        const url = try self.config.realtimeUrlAlloc(self.allocator);
        defer self.allocator.free(url);
        if (std.mem.startsWith(u8, url, "wss://")) {
            self.connection = .{ .secure = try ws.SecureClient.connect(self.allocator, random, url, .{}) };
        } else {
            self.connection = .{ .plain = try ws.Client.connect(self.allocator, random, url, .{}) };
        }
    }

    pub fn subscribe(self: *Client, topic: []const u8) !void {
        const ref_value = try self.nextRefAlloc();
        defer self.allocator.free(ref_value);

        const message = try phoenix.encodeAlloc(self.allocator, topic, "phx_join", phoenix.AccessTokenPayload{
            .access_token = self.access_token,
        }, ref_value, ref_value);
        defer self.allocator.free(message);

        try self.connection.sendText(message);
    }

    pub fn heartbeat(self: *Client) !void {
        const ref_value = try self.nextRefAlloc();
        defer self.allocator.free(ref_value);

        const message = try phoenix.encodeAlloc(self.allocator, "phoenix", "heartbeat", .{}, ref_value, null);
        defer self.allocator.free(message);
        try self.connection.sendText(message);
    }

    pub fn receive(self: *Client, scratch: []u8, allocator: std.mem.Allocator) !phoenix.Message {
        const msg = try self.connection.receive(scratch);
        defer switch (msg) {
            .text => |text| allocator.free(text),
            .binary => |bytes| allocator.free(bytes),
            .close => |close_msg| allocator.free(close_msg.reason),
        };

        return switch (msg) {
            .text => |text| try phoenix.decode(allocator, text),
            .binary => error.UnexpectedBinaryMessage,
            .close => error.ConnectionClosed,
        };
    }

    fn nextRefAlloc(self: *Client) ![]u8 {
        const current = self.next_ref;
        self.next_ref += 1;
        return try std.fmt.allocPrint(self.allocator, "{d}", .{current});
    }
};

test "realtime config builds wss url and join payload" {
    const cfg = config_mod.Config.init("https://demo.supabase.co", "anon");
    var client = Client.init(std.testing.allocator, cfg).withAccessToken("at");
    defer client.deinit();

    const message = try phoenix.encodeAlloc(std.testing.allocator, "realtime:public:todos", "phx_join", phoenix.AccessTokenPayload{
        .access_token = client.access_token,
    }, "1", "1");
    defer std.testing.allocator.free(message);

    try std.testing.expect(std.mem.indexOf(u8, message, "\"phx_join\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "\"access_token\":\"at\"") != null);
}
