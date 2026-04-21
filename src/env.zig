const std = @import("std");
const fs = @import("fs.zig");

pub const DotEnv = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,

    pub const Entry = struct {
        key: []u8,
        value: []u8,
    };

    pub fn get(self: DotEnv, key: []const u8) ?[]const u8 {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.key, key)) return entry.value;
        }
        return null;
    }

    pub fn deinit(self: *DotEnv) void {
        for (self.entries) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
        self.allocator.free(self.entries);
    }
};

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

pub fn parseDotEnv(allocator: std.mem.Allocator, input: []const u8) !DotEnv {
    var entries = std.ArrayList(DotEnv.Entry).empty;
    errdefer {
        for (entries.items) |entry| {
            allocator.free(entry.key);
            allocator.free(entry.value);
        }
        entries.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |raw_line| {
        var line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "export ")) {
            line = std.mem.trimLeft(u8, line["export ".len..], " \t");
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        var value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
            value = value[1 .. value.len - 1];
        }

        try entries.append(allocator, .{
            .key = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, value),
        });
    }

    return .{
        .allocator = allocator,
        .entries = try entries.toOwnedSlice(allocator),
    };
}

pub fn loadDotEnv(allocator: std.mem.Allocator, path: []const u8) !DotEnv {
    const input = try fs.readText(allocator, path);
    defer allocator.free(input);
    return try parseDotEnv(allocator, input);
}

pub fn getOrDotEnv(allocator: std.mem.Allocator, key: []const u8, dotenv_path: []const u8) !?[]u8 {
    if (try get(allocator, key)) |value| return value;
    if (!fs.exists(dotenv_path)) return null;

    var dotenv = try loadDotEnv(allocator, dotenv_path);
    defer dotenv.deinit();

    const value = dotenv.get(key) orelse return null;
    return try allocator.dupe(u8, value);
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

test "dotenv parser reads quoted values and comments" {
    var dotenv = try parseDotEnv(std.testing.allocator,
        \\# comment
        \\SUPABASE_URL=https://demo.supabase.co
        \\export SUPABASE_ANON_KEY="anon-key"
        \\PLAIN=value
    );
    defer dotenv.deinit();

    try std.testing.expectEqualStrings("https://demo.supabase.co", dotenv.get("SUPABASE_URL").?);
    try std.testing.expectEqualStrings("anon-key", dotenv.get("SUPABASE_ANON_KEY").?);
    try std.testing.expectEqualStrings("value", dotenv.get("PLAIN").?);
}
