const std = @import("std");

pub const ParamType = enum {
    string,
    integer,
    number,
    boolean,

    pub fn asString(self: ParamType) []const u8 {
        return @tagName(self);
    }
};

pub const Param = struct {
    name: []const u8,
    description: []const u8,
    ty: ParamType = .string,
    required: bool = true,
};

pub const Def = struct {
    name: []const u8,
    description: []const u8,
    params: []const Param = &.{},
};

pub const Call = struct {
    name: []const u8,
    arguments_json: []const u8,
};

pub const Result = struct {
    name: []const u8,
    ok: bool = true,
    content: []const u8,
};

pub fn renderCatalog(allocator: std.mem.Allocator, defs: []const Def) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    if (defs.len == 0) {
        try out.appendSlice(allocator, "No tools.");
        return out.toOwnedSlice(allocator);
    }

    for (defs, 0..) |tool_def, i| {
        if (i > 0) try out.appendSlice(allocator, "\n\n");
        try out.writer(allocator).print("- {s}: {s}", .{ tool_def.name, tool_def.description });
        if (tool_def.params.len > 0) {
            try out.appendSlice(allocator, "\n  params:");
            for (tool_def.params) |param| {
                try out.writer(allocator).print("\n  - {s} ({s}{s}): {s}", .{
                    param.name,
                    param.ty.asString(),
                    if (param.required) ", required" else "",
                    param.description,
                });
            }
        }
    }

    return out.toOwnedSlice(allocator);
}

test "catalog render includes tool names" {
    const alloc = std.testing.allocator;
    const out = try renderCatalog(alloc, &.{.{
        .name = "read_file",
        .description = "Read a file from disk",
    }});
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "read_file") != null);
}
