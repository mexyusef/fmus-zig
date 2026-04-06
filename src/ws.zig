const std = @import("std");

pub const Url = struct {
    secure: bool,
    host: []const u8,
    port: ?u16,
    path: []const u8,

    pub fn parse(input: []const u8) !Url {
        const secure = std.mem.startsWith(u8, input, "wss://");
        const plain = std.mem.startsWith(u8, input, "ws://");
        if (!secure and !plain) return error.InvalidWebSocketUrl;
        const rest = input[if (secure) 6 else 5 ..];
        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        const host_port = rest[0..slash];
        const path = if (slash < rest.len) rest[slash..] else "/";
        const colon = std.mem.lastIndexOfScalar(u8, host_port, ':');
        if (colon) |idx| {
            return .{
                .secure = secure,
                .host = host_port[0..idx],
                .port = try std.fmt.parseInt(u16, host_port[idx + 1 ..], 10),
                .path = path,
            };
        }
        return .{
            .secure = secure,
            .host = host_port,
            .port = null,
            .path = path,
        };
    }
};

pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

pub const Frame = struct {
    fin: bool = true,
    opcode: Opcode = .text,
    payload: []const u8,
};

test "websocket url parses host and path" {
    const url = try Url.parse("wss://example.com/socket");
    try std.testing.expect(url.secure);
    try std.testing.expectEqualStrings("example.com", url.host);
    try std.testing.expectEqualStrings("/socket", url.path);
}
