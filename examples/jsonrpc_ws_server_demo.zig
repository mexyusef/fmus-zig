const std = @import("std");
const fmus = @import("fmus");

fn ping(allocator: std.mem.Allocator, _: ?*anyopaque, _: ?std.json.Value) ![]u8 {
    return fmus.json.stringifyAlloc(allocator, .{ .pong = true });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = fmus.jsonrpc.Router.init(allocator);
    defer router.deinit();
    try router.add("ping", ping);

    var server = try std.net.Address.listen(try std.net.Address.parseIp("127.0.0.1", 9235), .{});
    defer server.deinit();

    const transport = fmus.jsonrpc.WsTransportServer.init(allocator, &router, .{
        .ws = .{ .protocol = "jsonrpc.2.0" },
    });

    std.debug.print("fmus jsonrpc ws server listening on ws://127.0.0.1:9235/ws\n", .{});

    while (true) {
        const accepted = try server.accept();
        errdefer accepted.stream.close();
        var handshake_buf: [8192]u8 = undefined;
        var scratch: [8192]u8 = undefined;
        try transport.serveAccepted(accepted.stream, &handshake_buf, &scratch);
    }
}
