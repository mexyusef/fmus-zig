const std = @import("std");

pub fn field(body: []const u8, name: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, body, '&');
    while (iter.next()) |part| {
        var kv = std.mem.splitScalar(u8, part, '=');
        const key = kv.next() orelse continue;
        const value = kv.next() orelse "";
        if (std.mem.eql(u8, key, name)) return value;
    }
    return null;
}

pub fn queryField(target: []const u8, name: []const u8) ?[]const u8 {
    const qmark = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    return field(target[qmark + 1 ..], name);
}

pub fn decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (ch == '+') {
            try out.append(allocator, ' ');
            continue;
        }
        if (ch == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch {
                try out.append(allocator, ch);
                continue;
            };
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch {
                try out.append(allocator, ch);
                continue;
            };
            try out.append(allocator, @as(u8, @intCast((hi << 4) | lo)));
            i += 2;
            continue;
        }
        try out.append(allocator, ch);
    }
    return try out.toOwnedSlice(allocator);
}

test "query field parses" {
    try std.testing.expectEqualStrings("abc", queryField("/x?a=abc&b=1", "a").?);
}
