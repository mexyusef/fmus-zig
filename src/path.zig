const std = @import("std");

pub fn join(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return std.fs.path.join(allocator, parts);
}

pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

pub fn extension(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

pub fn stem(path: []const u8) []const u8 {
    const base = basename(path);
    const ext = std.fs.path.extension(base);
    if (ext.len == 0) return base;
    return base[0 .. base.len - ext.len];
}

pub fn parent(path: []const u8) ?[]const u8 {
    return std.fs.path.dirname(path);
}

pub fn isAbs(path: []const u8) bool {
    return std.fs.path.isAbsolute(path);
}

pub fn normalizeSep(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, input);
    if (@import("builtin").os.tag == .windows) {
        for (out) |*c| {
            if (c.* == '/') c.* = '\\';
        }
    } else {
        for (out) |*c| {
            if (c.* == '\\') c.* = '/';
        }
    }
    return out;
}

pub fn userHome(allocator: std.mem.Allocator) ![]u8 {
    if (@import("builtin").os.tag == .windows) {
        if (try @import("env.zig").get(allocator, "USERPROFILE")) |value| return value;
        const drive = (try @import("env.zig").get(allocator, "HOMEDRIVE")) orelse "";
        defer if (drive.len > 0) allocator.free(drive);
        const path_part = (try @import("env.zig").get(allocator, "HOMEPATH")) orelse "";
        defer if (path_part.len > 0) allocator.free(path_part);
        if (drive.len > 0 and path_part.len > 0) {
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ drive, path_part });
        }
    }
    return try @import("env.zig").require(allocator, "HOME");
}

pub fn expandUser(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len == 0 or input[0] != '~') return try allocator.dupe(u8, input);
    const home = try userHome(allocator);
    defer allocator.free(home);
    if (input.len == 1) return try allocator.dupe(u8, home);
    if (input[1] == '/' or input[1] == '\\') {
        return try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{
            home,
            std.fs.path.sep,
            input[2..],
        });
    }
    return try allocator.dupe(u8, input);
}

test "stem strips extension" {
    try std.testing.expectEqualStrings("file", stem("a/b/file.txt"));
}

test "parent returns containing directory" {
    try std.testing.expectEqualStrings("a/b", parent("a/b/file.txt").?);
}

test "expand user expands tilde path" {
    const alloc = std.testing.allocator;
    const out = try expandUser(alloc, "~");
    defer alloc.free(out);
    try std.testing.expect(out.len > 0);
}
