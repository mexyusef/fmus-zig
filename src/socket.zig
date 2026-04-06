const std = @import("std");

pub fn recv(handle: std.net.Stream.Handle, buffer: []u8) !usize {
    if (@import("builtin").os.tag == .windows) {
        const rc = std.os.windows.recvfrom(handle, buffer.ptr, buffer.len, 0, null, null);
        if (rc == 0) return 0;
        if (rc == std.os.windows.ws2_32.SOCKET_ERROR) return error.Unexpected;
        return @intCast(rc);
    }
    return try std.posix.recv(handle, buffer, 0);
}

pub fn sendAll(handle: std.net.Stream.Handle, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        if (@import("builtin").os.tag == .windows) {
            const rc = std.os.windows.sendto(handle, bytes[offset..].ptr, bytes.len - offset, 0, null, 0);
            if (rc == std.os.windows.ws2_32.SOCKET_ERROR) return error.Unexpected;
            offset += @intCast(rc);
        } else {
            offset += try std.posix.send(handle, bytes[offset..], 0);
        }
    }
}

test "socket module compiles" {
    try std.testing.expect(true);
}
