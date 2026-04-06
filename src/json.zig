const std = @import("std");

pub fn parse(allocator: std.mem.Allocator, comptime T: type, input: []const u8) !T {
    return try std.json.parseFromSliceLeaky(T, allocator, input, .{ .allocate = .alloc_always });
}

pub fn parseOwned(allocator: std.mem.Allocator, comptime T: type, input: []const u8) !std.json.Parsed(T) {
    return try std.json.parseFromSlice(T, allocator, input, .{ .allocate = .alloc_always });
}

pub fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

pub fn prettyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(value, .{ .whitespace = .indent_2 }, &out.writer);
    return try out.toOwnedSlice();
}

pub fn parseFile(allocator: std.mem.Allocator, comptime T: type, path: []const u8) !T {
    const fs = @import("fs.zig");
    const input = try fs.read(allocator, path);
    defer allocator.free(input);
    return try parse(allocator, T, input);
}

test "parse reads simple object" {
    const Obj = struct { name: []const u8 };
    const parsed = try parse(std.heap.page_allocator, Obj, "{\"name\":\"zig\"}");
    try std.testing.expectEqualStrings("zig", parsed.name);
}

test "pretty alloc formats json" {
    const alloc = std.testing.allocator;
    const out = try prettyAlloc(alloc, .{ .name = "zig" });
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n") != null);
}
