const std = @import("std");

pub const StreamConfig = struct {
    max_frame_len: usize = 4 * 1024 * 1024,
};

pub fn readDelimitedFrameAlloc(
    allocator: std.mem.Allocator,
    reader: anytype,
    delimiter: []const u8,
    config: StreamConfig,
) !?[]u8 {
    if (delimiter.len == 0) return error.EmptyDelimiter;

    var buffer = std.array_list.Managed(u8).init(allocator);
    errdefer buffer.deinit();

    while (true) {
        const byte = reader.*.takeByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (buffer.items.len == 0) return null;
                return try buffer.toOwnedSlice();
            },
            else => return err,
        };

        try buffer.append(byte);
        if (buffer.items.len > config.max_frame_len) return error.FrameTooLarge;
        if (std.mem.endsWith(u8, buffer.items, delimiter)) {
            buffer.items.len -= delimiter.len;
            return try buffer.toOwnedSlice();
        }
    }
}

pub fn writeDelimitedFrame(writer: anytype, delimiter: []const u8, payload: []const u8) !void {
    try writer.writeAll(payload);
    try writer.writeAll(delimiter);
}

pub fn readContentLengthFrameAlloc(
    allocator: std.mem.Allocator,
    reader: anytype,
    config: StreamConfig,
) !?[]u8 {
    var header_bytes = std.array_list.Managed(u8).init(allocator);
    defer header_bytes.deinit();

    while (true) {
        const byte = reader.*.takeByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (header_bytes.items.len == 0) return null;
                return error.UnexpectedEndOfStream;
            },
            else => return err,
        };
        try header_bytes.append(byte);
        if (header_bytes.items.len > config.max_frame_len) return error.FrameTooLarge;
        if (std.mem.endsWith(u8, header_bytes.items, "\r\n\r\n")) break;
    }

    const header_text = header_bytes.items;
    var lines = std.mem.splitSequence(u8, header_text, "\r\n");
    var content_length: ?usize = null;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.ascii.startsWithIgnoreCase(line, "Content-Length:")) {
            const value = std.mem.trim(u8, line["Content-Length:".len..], " \t");
            content_length = try std.fmt.parseInt(usize, value, 10);
        }
    }

    const frame_len = content_length orelse return error.MissingContentLength;
    if (frame_len > config.max_frame_len) return error.FrameTooLarge;

    const payload = try allocator.alloc(u8, frame_len);
    errdefer allocator.free(payload);
    try reader.*.readSliceAll(payload);
    return payload;
}

pub fn writeContentLengthFrame(writer: anytype, payload: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{payload.len});
    try writer.writeAll(payload);
}

test "read and write delimited jsonrpc frame" {
    const allocator = std.testing.allocator;
    var data = std.Io.Reader.fixed("{\"jsonrpc\":\"2.0\"}\n");
    const payload = try readDelimitedFrameAlloc(allocator, &data, "\n", .{});
    defer allocator.free(payload.?);
    try std.testing.expect(std.mem.eql(u8, payload.?, "{\"jsonrpc\":\"2.0\"}"));
}

test "read and write content length frame" {
    const allocator = std.testing.allocator;
    const payload_text = "{\"jsonrpc\":\"2.0\"}";
    const framed = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n\r\n{s}", .{ payload_text.len, payload_text });
    defer allocator.free(framed);
    var data = std.Io.Reader.fixed(framed);
    const payload = try readContentLengthFrameAlloc(allocator, &data, .{});
    defer allocator.free(payload.?);
    try std.testing.expect(std.mem.eql(u8, payload.?, payload_text));
}
