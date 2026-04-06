const std = @import("std");

pub fn lines(allocator: std.mem.Allocator, input: []const u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).empty;
    defer out.deinit(allocator);

    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        try out.append(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

pub fn trim(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, " \r\n\t");
}

pub fn split(allocator: std.mem.Allocator, input: []const u8, delim: u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).empty;
    defer out.deinit(allocator);
    var it = std.mem.splitScalar(u8, input, delim);
    while (it.next()) |part| try out.append(allocator, part);
    return out.toOwnedSlice(allocator);
}

pub fn indentAlloc(allocator: std.mem.Allocator, input: []const u8, prefix: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |line| {
        if (!first) try out.append(allocator, '\n');
        first = false;
        try out.appendSlice(allocator, prefix);
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

pub fn slugAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var pending_dash = false;
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (pending_dash and out.items.len > 0) try out.append(allocator, '-');
            pending_dash = false;
            try out.append(allocator, std.ascii.toLower(c));
        } else if (out.items.len > 0) {
            pending_dash = true;
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn startsWith(input: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, input, prefix);
}

pub fn endsWith(input: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, input, suffix);
}

test "trim removes whitespace" {
    try std.testing.expectEqualStrings("hello", trim(" \r\nhello\t "));
}

test "slug alloc normalizes text" {
    const alloc = std.testing.allocator;
    const slug = try slugAlloc(alloc, "Hello, World From Zig");
    defer alloc.free(slug);
    try std.testing.expectEqualStrings("hello-world-from-zig", slug);
}
