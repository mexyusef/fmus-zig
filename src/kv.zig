const std = @import("std");
const fs = @import("fs.zig");
const json = @import("json.zig");

pub const Entry = struct {
    key: []const u8,
    value: []const u8,
};

pub const FileStore = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    map: std.StringHashMapUnmanaged([]u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) FileStore {
        return .{ .allocator = allocator, .path = path };
    }

    pub fn deinit(self: *FileStore) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit(self.allocator);
    }

    pub fn set(self: *FileStore, key: []const u8, value: []const u8) !void {
        const gop = try self.map.getOrPut(self.allocator, try self.allocator.dupe(u8, key));
        if (gop.found_existing) {
            self.allocator.free(gop.value_ptr.*);
        }
        gop.value_ptr.* = try self.allocator.dupe(u8, value);
    }

    pub fn get(self: *const FileStore, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn save(self: *FileStore) !void {
        var entries = std.ArrayList(Entry).empty;
        defer entries.deinit(self.allocator);
        var it = self.map.iterator();
        while (it.next()) |entry| {
            try entries.append(self.allocator, .{
                .key = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            });
        }
        try fs.writeJson(self.path, .{ .entries = entries.items });
    }

    pub fn load(self: *FileStore) !void {
        if (!fs.exists(self.path)) return;
        const Parsed = struct { entries: []const Entry };
        const parsed = try json.parseFile(self.allocator, Parsed, self.path);
        for (parsed.entries) |entry| {
            try self.set(entry.key, entry.value);
        }
    }
};

test "kv store roundtrip" {
    const path = "__fmus_kv_test.json";
    defer fs.remove(path) catch {};
    var kv = FileStore.init(std.heap.page_allocator, path);
    defer kv.deinit();
    try kv.set("name", "zig");
    try kv.save();
    var kv2 = FileStore.init(std.heap.page_allocator, path);
    defer kv2.deinit();
    try kv2.load();
    try std.testing.expectEqualStrings("zig", kv2.get("name").?);
}
