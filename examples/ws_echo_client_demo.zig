const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));

    var client = try fmus.ws.Client.connect(allocator, prng.random(), "ws://127.0.0.1:9225/ws", .{});
    defer client.deinit();

    try client.sendText("hello from fmus ws client");

    var scratch: [8192]u8 = undefined;
    const msg = try client.receive(&scratch);
    switch (msg) {
        .text => |text| {
            defer allocator.free(text);
            try std.fs.File.stdout().writeAll(text);
            try std.fs.File.stdout().writeAll("\n");
        },
        .binary => |bytes| {
            defer allocator.free(bytes);
            try std.fs.File.stdout().writeAll(bytes);
            try std.fs.File.stdout().writeAll("\n");
        },
        .close => |close_msg| {
            defer allocator.free(close_msg.reason);
            std.debug.print("server closed connection: {?} {s}\n", .{ close_msg.code, close_msg.reason });
        },
    }

    try client.close(.normal, "done");
}
