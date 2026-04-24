const std = @import("std");
const types = @import("types.zig");
const router_mod = @import("router.zig");
const ws = @import("../ws.zig");
const ws_server = @import("../ws_server.zig");

pub const Config = struct {
    ws: ws_server.Config = .{},
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    router: *const router_mod.Router,
    config: Config = .{},

    pub fn init(allocator: std.mem.Allocator, router: *const router_mod.Router, config: Config) Server {
        return .{
            .allocator = allocator,
            .router = router,
            .config = config,
        };
    }

    pub fn serveAccepted(self: *const Server, stream: std.net.Stream, handshake_buffer: []u8, scratch: []u8) !void {
        var session = try ws_server.Session.accept(self.allocator, stream, handshake_buffer, self.config.ws);
        defer session.deinit();

        while (true) {
            const message = session.receive(scratch) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            switch (message) {
                .text => |text| {
                    defer self.allocator.free(text);
                    try self.handleText(&session, text);
                },
                .binary => |bytes| {
                    defer self.allocator.free(bytes);
                    const response = try types.errorJsonAlloc(
                        self.allocator,
                        .null,
                        @intFromEnum(types.StandardErrorCode.invalid_request),
                        "\"binary websocket frames are not valid json-rpc payloads\"",
                        null,
                    );
                    defer self.allocator.free(response);
                    try session.enqueueText(response);
                    try session.flush();
                },
                .close => |close_message| {
                    defer self.allocator.free(close_message.reason);
                    break;
                },
            }
        }
    }

    fn handleText(self: *const Server, session: *ws_server.Session, text: []const u8) !void {
        var document = types.parseMessageAlloc(self.allocator, text) catch {
            const response = try types.errorJsonAlloc(
                self.allocator,
                .null,
                @intFromEnum(types.StandardErrorCode.parse_error),
                "\"invalid json-rpc payload\"",
                null,
            );
            defer self.allocator.free(response);
            try session.enqueueText(response);
            try session.flush();
            return;
        };
        defer document.deinit();

        const response = try self.router.dispatchDocumentAlloc(self.allocator, &document);
        if (response) |json| {
            defer self.allocator.free(json);
            try session.enqueueText(json);
            try session.flush();
        }
    }
};

test "jsonrpc ws transport compiles" {
    var router = router_mod.Router.init(std.testing.allocator);
    defer router.deinit();
    const server = Server.init(std.testing.allocator, &router, .{});
    _ = server;
    try std.testing.expect(true);
}
