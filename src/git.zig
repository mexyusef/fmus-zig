const std = @import("std");
const proc = @import("proc.zig");
const text = @import("text.zig");

pub fn isRepo(allocator: std.mem.Allocator, cwd: []const u8) bool {
    var out = proc.cmd(&.{ "git", "rev-parse", "--is-inside-work-tree" }).in(cwd).run(allocator) catch return false;
    defer out.deinit();
    return out.ok() and std.mem.eql(u8, text.trim(out.stdout), "true");
}

pub fn currentBranch(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    const out = try proc.cmd(&.{ "git", "branch", "--show-current" }).in(cwd).text(allocator);
    const trimmed = text.trim(out);
    if (trimmed.len == out.len) return out;
    defer allocator.free(out);
    return try allocator.dupe(u8, trimmed);
}

pub fn root(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    const out = try proc.cmd(&.{ "git", "rev-parse", "--show-toplevel" }).in(cwd).text(allocator);
    const trimmed = text.trim(out);
    if (trimmed.len == out.len) return out;
    defer allocator.free(out);
    return try allocator.dupe(u8, trimmed);
}

pub fn statusShort(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    return try proc.cmd(&.{ "git", "status", "--short" }).in(cwd).text(allocator);
}

test "current project is a git repo" {
    try std.testing.expect(isRepo(std.testing.allocator, "."));
}
