const std = @import("std");
const json = @import("json.zig");

pub fn read(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
}

pub fn readText(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return read(allocator, path);
}

pub fn write(path: []const u8, data: []const u8) !void {
    return std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
}

pub fn writeText(path: []const u8, text: []const u8) !void {
    return write(path, text);
}

pub fn append(path: []const u8, data: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
    defer file.close();
    try file.seekFromEnd(0);
    try file.writeAll(data);
}

pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn mkdirp(path: []const u8) !void {
    return std.fs.cwd().makePath(path);
}

pub fn remove(path: []const u8) !void {
    return std.fs.cwd().deleteFile(path);
}

pub fn readJson(allocator: std.mem.Allocator, comptime T: type, path: []const u8) !T {
    const input = try read(allocator, path);
    defer allocator.free(input);
    return try json.parse(allocator, T, input);
}

pub fn writeJson(path: []const u8, value: anytype) !void {
    const allocator = std.heap.page_allocator;
    const output = try json.prettyAlloc(allocator, value);
    defer allocator.free(output);
    try write(path, output);
}

test "exists detects missing file" {
    try std.testing.expect(!exists("__definitely_missing_fmus_file__"));
}

test "write and read text roundtrip" {
    const alloc = std.testing.allocator;
    const tmp_name = "fmus_fs_roundtrip.txt";
    defer std.fs.cwd().deleteFile(tmp_name) catch {};

    try writeText(tmp_name, "hello");
    const out = try readText(alloc, tmp_name);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("hello", out);
}
