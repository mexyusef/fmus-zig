const std = @import("std");
const json = @import("json.zig");

pub const Request = struct {
    id: []const u8,
    method: []const u8,
    params_json: ?[]const u8 = null,
};

pub const Response = struct {
    id: []const u8,
    ok: bool,
    result_json: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
};

pub fn ok(allocator: std.mem.Allocator, id: []const u8, result: anytype) ![]u8 {
    const result_json = try json.stringifyAlloc(allocator, result);
    defer allocator.free(result_json);

    return try json.prettyAlloc(allocator, Response{
        .id = id,
        .ok = true,
        .result_json = result_json,
    });
}

test "rpc response encodes ok flag" {
    const alloc = std.testing.allocator;
    const out = try ok(alloc, "1", .{ .hello = "world" });
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ok\": true") != null);
}
