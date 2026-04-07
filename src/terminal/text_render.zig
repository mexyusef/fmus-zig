const std = @import("std");
const snapshot = @import("snapshot.zig");
const state_mod = @import("state.zig");

pub fn write(writer: anytype, state: *const state_mod.State) !void {
    const alloc = std.heap.page_allocator;
    const out = try snapshot.renderAlloc(alloc, state);
    defer alloc.free(out);
    try writer.writeAll(out);
}
