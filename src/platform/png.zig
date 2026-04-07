const std = @import("std");

pub fn encodeRgba8Alloc(allocator: std.mem.Allocator, width: u32, height: u32, rgba: []const u8) ![]u8 {
    if (rgba.len != @as(usize, width) * @as(usize, height) * 4) return error.InvalidPixelBuffer;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var writer = out.writer(allocator);

    try writer.writeAll(&[_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A });

    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8;
    ihdr[9] = 6;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try writeChunk(&writer, "IHDR", &ihdr);

    var filtered = std.ArrayList(u8).empty;
    defer filtered.deinit(allocator);
    try filtered.ensureTotalCapacityPrecise(allocator, rgba.len + @as(usize, height));
    const stride = @as(usize, width) * 4;
    var row: usize = 0;
    while (row < height) : (row += 1) {
        try filtered.append(allocator, 0);
        const off = row * stride;
        try filtered.appendSlice(allocator, rgba[off .. off + stride]);
    }

    var compressed = std.ArrayList(u8).empty;
    defer compressed.deinit(allocator);
    try writeStoredZlib(allocator, &compressed, filtered.items);

    try writeChunk(&writer, "IDAT", compressed.items);
    try writeChunk(&writer, "IEND", "");
    return try out.toOwnedSlice(allocator);
}

fn writeStoredZlib(allocator: std.mem.Allocator, out: *std.ArrayList(u8), data: []const u8) !void {
    try out.appendSlice(allocator, &[_]u8{ 0x78, 0x01 });
    var remaining = data;
    while (remaining.len != 0) {
        const chunk_len = @min(remaining.len, 65535);
        const final_block: u8 = if (chunk_len == remaining.len) 1 else 0;
        try out.append(allocator, final_block);
        var len_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &len_buf, @intCast(chunk_len), .little);
        try out.appendSlice(allocator, &len_buf);
        std.mem.writeInt(u16, &len_buf, ~@as(u16, @intCast(chunk_len)), .little);
        try out.appendSlice(allocator, &len_buf);
        try out.appendSlice(allocator, remaining[0..chunk_len]);
        remaining = remaining[chunk_len..];
    }
    const adler = std.hash.Adler32.hash(data);
    var adler_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &adler_buf, adler, .big);
    try out.appendSlice(allocator, &adler_buf);
}

fn writeChunk(writer: anytype, comptime kind: []const u8, data: []const u8) !void {
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @intCast(data.len), .big);
    try writer.writeAll(&len_buf);
    try writer.writeAll(kind);
    try writer.writeAll(data);

    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    var crc_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_buf, crc.final(), .big);
    try writer.writeAll(&crc_buf);
}

test "png writer emits signature and chunks" {
    const rgba = [_]u8{
        0xff, 0x00, 0x00, 0xff,
        0x00, 0xff, 0x00, 0xff,
        0x00, 0x00, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff,
    };
    const png_bytes = try encodeRgba8Alloc(std.testing.allocator, 2, 2, &rgba);
    defer std.testing.allocator.free(png_bytes);
    try std.testing.expect(png_bytes.len > 32);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A }, png_bytes[0..8]);
}
