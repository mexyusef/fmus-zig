const std = @import("std");

pub const RuntimeModel = struct {
    provider: []const u8,
    id: []const u8,
    api: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
};

pub const PreparedAuth = struct {
    mode: []const u8,
    token: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
};

pub const FailoverContext = struct {
    provider: []const u8,
    model: []const u8,
    error_message: []const u8,
};

pub fn normalizeModelId(allocator: std.mem.Allocator, provider_name: []const u8, model_id: []const u8) ![]u8 {
    const out = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ provider_name, model_id });
    _ = std.ascii.lowerString(out, out);
    return out;
}

test "provider model id normalizes" {
    const alloc = std.testing.allocator;
    const out = try normalizeModelId(alloc, "OpenAI", "GPT-4.1");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("openai/gpt-4.1", out);
}
