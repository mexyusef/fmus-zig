const std = @import("std");
const ws = @import("ws.zig");
const http_server = @import("http_server.zig");

pub const AuthDecision = union(enum) {
    allow,
    reject: struct {
        status: u16 = 403,
        body: []const u8 = "forbidden",
        content_type: []const u8 = "text/plain",
        headers: []const http_server.Header = &.{},
    },
};

pub const AuthHook = *const fn (ctx: ?*anyopaque, request: ws.HandshakeRequest) anyerror!AuthDecision;

pub const QueueConfig = struct {
    max_messages: usize = 64,
    max_bytes: usize = 1024 * 1024,
};

pub const Config = struct {
    protocol: ?[]const u8 = null,
    extra_headers: []const ws.UpgradeResponse.Header = &.{},
    max_payload_len: u64 = 16 * 1024 * 1024,
    queue: QueueConfig = .{},
    auth: ?AuthHook = null,
    ctx: ?*anyopaque = null,
};

pub const Error = anyerror;

const QueuedMessage = union(enum) {
    text: []u8,
    binary: []u8,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    conn: ws.ServerConn,
    queue_cfg: QueueConfig,
    outbound: std.ArrayListUnmanaged(QueuedMessage) = .empty,
    outbound_bytes: usize = 0,

    pub fn accept(allocator: std.mem.Allocator, stream: std.net.Stream, handshake_buffer: []u8, config: Config) Error!Session {
        const read_result = try ws.readHandshakeRequest(stream.handle, handshake_buffer);
        const handshake = read_result.request;

        if (config.auth) |auth| {
            const decision = try auth(config.ctx, handshake);
            switch (decision) {
                .allow => {},
                .reject => |reject| {
                    try http_server.writeResponse(stream.handle, .{
                        .status = reject.status,
                        .content_type = reject.content_type,
                        .body = reject.body,
                        .extra_headers = reject.headers,
                    });
                    stream.close();
                    return Error.AuthRejected;
                },
            }
        }

        const conn = try ws.ServerConn.accept(allocator, stream, handshake_buffer[0..read_result.raw_len], .{
            .protocol = config.protocol,
            .extra_headers = config.extra_headers,
            .max_payload_len = config.max_payload_len,
        });
        return .{
            .allocator = allocator,
            .conn = conn,
            .queue_cfg = config.queue,
        };
    }

    pub fn deinit(self: *Session) void {
        for (self.outbound.items) |item| {
            switch (item) {
                .text => |text| self.allocator.free(text),
                .binary => |bytes| self.allocator.free(bytes),
            }
        }
        self.outbound.deinit(self.allocator);
        self.conn.deinit();
    }

    pub fn receive(self: *Session, scratch: []u8) !ws.Message {
        return self.conn.receive(scratch);
    }

    pub fn enqueueText(self: *Session, text: []const u8) Error!void {
        try self.ensureQueueCapacity(text.len);
        try self.outbound.append(self.allocator, .{ .text = try self.allocator.dupe(u8, text) });
        self.outbound_bytes += text.len;
    }

    pub fn enqueueBinary(self: *Session, bytes: []const u8) Error!void {
        try self.ensureQueueCapacity(bytes.len);
        try self.outbound.append(self.allocator, .{ .binary = try self.allocator.dupe(u8, bytes) });
        self.outbound_bytes += bytes.len;
    }

    pub fn flush(self: *Session) !void {
        for (self.outbound.items) |item| {
            switch (item) {
                .text => |text| {
                    defer self.allocator.free(text);
                    try self.conn.sendText(text);
                },
                .binary => |bytes| {
                    defer self.allocator.free(bytes);
                    try self.conn.sendBinary(bytes);
                },
            }
        }
        self.outbound.clearRetainingCapacity();
        self.outbound_bytes = 0;
    }

    fn ensureQueueCapacity(self: *Session, payload_len: usize) Error!void {
        if (self.outbound.items.len >= self.queue_cfg.max_messages) return Error.OutboundQueueFull;
        if (self.outbound_bytes + payload_len > self.queue_cfg.max_bytes) return Error.OutboundQueueFull;
    }
};

test "ws server queue enforces limits" {
    const allocator = std.testing.allocator;
    const fake_conn: ws.ServerConn = undefined;
    var session = Session{
        .allocator = allocator,
        .conn = fake_conn,
        .queue_cfg = .{ .max_messages = 1, .max_bytes = 4 },
    };
    defer {
        for (session.outbound.items) |item| {
            switch (item) {
                .text => |text| allocator.free(text),
                .binary => |bytes| allocator.free(bytes),
            }
        }
        session.outbound.deinit(allocator);
    }

    try session.enqueueText("ok");
    try std.testing.expectError(Error.OutboundQueueFull, session.enqueueText("xx"));
}
