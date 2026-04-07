const std = @import("std");
const paint_mod = @import("paint.zig");
const json = @import("../json.zig");

pub const PersistedState = struct {
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    theme: ThemeName = .default,
};

pub const ThemeName = enum {
    default,
    mac_bw,
    amber,

    pub fn toPreset(self: ThemeName) paint_mod.ThemePreset {
        return switch (self) {
            .default => .default,
            .mac_bw => .mac_bw,
            .amber => .amber,
        };
    }

    pub fn fromPreset(preset: paint_mod.ThemePreset) ThemeName {
        return switch (preset) {
            .default => .default,
            .mac_bw => .mac_bw,
            .amber => .amber,
        };
    }
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !PersistedState {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const text = try file.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(text);
    const parsed = try std.json.parseFromSlice(PersistedState, allocator, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

pub fn save(path: []const u8, state: PersistedState) !void {
    const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    const text = try json.prettyAlloc(std.heap.page_allocator, state);
    defer std.heap.page_allocator.free(text);
    try file.writeAll(text);
}

test "settings roundtrip json" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try std.json.Stringify.value(PersistedState{
        .width = 1,
        .height = 2,
        .x = 3,
        .y = 4,
        .theme = .amber,
    }, .{}, &out.writer);
    const parsed = try std.json.parseFromSlice(PersistedState, std.testing.allocator, out.written(), .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 1), parsed.value.width);
    try std.testing.expectEqual(ThemeName.amber, parsed.value.theme);
}
