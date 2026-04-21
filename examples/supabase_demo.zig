const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var loaded = try fmus.supabase.config.loadFromEnvFileOrProcess(allocator, "..\\.env", .anon);
    defer loaded.deinit();

    const client = fmus.supabase.Client.init(allocator, loaded.config);

    var query = try client.from("todos");
    defer query.deinit();

    _ = try query.select("id,title,done");
    _ = try query.eq("done", "false");
    _ = try query.limit(10);

    const preview_url = try query.buildUrlAlloc();
    defer allocator.free(preview_url);

    std.debug.print("Preview REST URL: {s}\n", .{preview_url});
    std.debug.print("Supabase project: {s}\n", .{loaded.config.url});
}
