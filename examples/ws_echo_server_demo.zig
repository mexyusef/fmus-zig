const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try std.net.Address.listen(try std.net.Address.parseIp("127.0.0.1", 9225), .{});
    defer server.deinit();

    std.debug.print("fmus ws echo server listening on ws://127.0.0.1:9225/ws\n", .{});

    while (true) {
        const accepted = try server.accept();
        errdefer accepted.stream.close();

        var handshake_buf: [8192]u8 = undefined;
        var conn = try fmus.ws.ServerConn.readAndAccept(allocator, accepted.stream, &handshake_buf, .{});
        defer conn.deinit();

        var scratch: [8192]u8 = undefined;
        while (true) {
            const msg = conn.receive(&scratch) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            switch (msg) {
                .text => |text| {
                    defer allocator.free(text);
                    try conn.sendText(text);
                },
                .binary => |bytes| {
                    defer allocator.free(bytes);
                    try conn.sendBinary(bytes);
                },
                .close => |close_msg| {
                    defer allocator.free(close_msg.reason);
                    break;
                },
            }
        }
    }
}
