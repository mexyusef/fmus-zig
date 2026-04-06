const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const slug = try fmus.text.slugAlloc(allocator, "FMUS Zig Core Demo");
    const joined = try fmus.path.join(allocator, &.{ "examples", "core_demo.zig" });
    const pretty = try fmus.json.prettyAlloc(allocator, .{
        .slug = slug,
        .path = joined,
        .stem = fmus.path.stem(joined),
    });

    try std.fs.File.stdout().writeAll(pretty);
    try std.fs.File.stdout().writeAll("\n");
}
