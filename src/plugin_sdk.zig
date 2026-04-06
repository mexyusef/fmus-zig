const std = @import("std");
const capability = @import("capability.zig");
const plugin_contract = @import("plugin_contract.zig");

pub const Entry = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    capabilities: []const capability.Decl = &.{},
    compatibility: plugin_contract.Compatibility = .{},
};

pub fn define(
    id: []const u8,
    name: []const u8,
    description: []const u8,
    capabilities: []const capability.Decl,
) Entry {
    return .{
        .id = id,
        .name = name,
        .description = description,
        .capabilities = capabilities,
    };
}

test "plugin sdk define builds entry" {
    const e = define("browser", "Browser", "Browser plugin", &.{});
    try std.testing.expectEqualStrings("browser", e.id);
}
