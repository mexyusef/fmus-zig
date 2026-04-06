const std = @import("std");

pub fn exists(key: []const u8) bool {
    return std.process.hasEnvVar(std.heap.page_allocator, key) catch false;
}

pub fn get(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => err,
    };
}

pub fn require(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    return (try get(allocator, key)) orelse error.MissingEnvVar;
}

pub fn getOr(allocator: std.mem.Allocator, key: []const u8, fallback: []const u8) ![]u8 {
    return (try get(allocator, key)) orelse try allocator.dupe(u8, fallback);
}

pub fn parseBoolValue(input: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(input, "1")) return true;
    if (std.ascii.eqlIgnoreCase(input, "true")) return true;
    if (std.ascii.eqlIgnoreCase(input, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(input, "on")) return true;
    if (std.ascii.eqlIgnoreCase(input, "0")) return false;
    if (std.ascii.eqlIgnoreCase(input, "false")) return false;
    if (std.ascii.eqlIgnoreCase(input, "no")) return false;
    if (std.ascii.eqlIgnoreCase(input, "off")) return false;
    return null;
}

pub fn boolVar(allocator: std.mem.Allocator, key: []const u8) !?bool {
    const raw = (try get(allocator, key)) orelse return null;
    defer allocator.free(raw);
    return parseBoolValue(raw);
}

pub fn int(comptime T: type, allocator: std.mem.Allocator, key: []const u8) !?T {
    const raw = (try get(allocator, key)) orelse return null;
    defer allocator.free(raw);
    return try std.fmt.parseInt(T, raw, 10);
}

test "parse bool value accepts common variants" {
    try std.testing.expectEqual(@as(?bool, true), parseBoolValue("true"));
    try std.testing.expectEqual(@as(?bool, false), parseBoolValue("off"));
    try std.testing.expectEqual(@as(?bool, null), parseBoolValue("maybe"));
}

test "get or falls back" {
    const alloc = std.testing.allocator;
    const out = try getOr(alloc, "__FMUS_ENV_MISSING__", "fallback");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("fallback", out);
}
