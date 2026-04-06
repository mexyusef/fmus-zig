const std = @import("std");
const text = @import("text.zig");

pub const Event = struct {
    event: ?[]const u8 = null,
    data: []const u8 = "",
    id: ?[]const u8 = null,
    retry_ms: ?u64 = null,
};

pub fn parseBlock(allocator: std.mem.Allocator, block: []const u8) !Event {
    var evt: Event = .{};
    var data_lines = std.ArrayList([]const u8).empty;
    defer data_lines.deinit(allocator);

    var lines = std.mem.splitScalar(u8, block, '\n');
    while (lines.next()) |raw_line| {
        const line = text.trim(raw_line);
        if (line.len == 0) continue;
        if (line[0] == ':') continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse {
            if (std.mem.eql(u8, line, "data")) try data_lines.append(allocator, "");
            continue;
        };
        const key = line[0..colon];
        const value = std.mem.trimLeft(u8, line[colon + 1 ..], " ");
        if (std.mem.eql(u8, key, "event")) evt.event = try allocator.dupe(u8, value)
        else if (std.mem.eql(u8, key, "data")) try data_lines.append(allocator, try allocator.dupe(u8, value))
        else if (std.mem.eql(u8, key, "id")) evt.id = try allocator.dupe(u8, value)
        else if (std.mem.eql(u8, key, "retry")) evt.retry_ms = try std.fmt.parseInt(u64, value, 10);
    }

    if (data_lines.items.len == 0) {
        evt.data = try allocator.dupe(u8, "");
        return evt;
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (data_lines.items, 0..) |line, i| {
        defer allocator.free(line);
        if (i > 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, line);
    }
    evt.data = try out.toOwnedSlice(allocator);
    return evt;
}

test "parse block reads event and data" {
    const alloc = std.testing.allocator;
    const evt = try parseBlock(alloc,
        \\event: message
        \\data: hello
    );
    defer alloc.free(evt.event.?);
    defer alloc.free(evt.data);
    try std.testing.expectEqualStrings("message", evt.event.?);
    try std.testing.expectEqualStrings("hello", evt.data);
}
