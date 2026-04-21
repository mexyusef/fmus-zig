const std = @import("std");
const fmus = @import("src/fmus.zig");

const DocumentRow = struct {
    id: []const u8,
    title: ?[]const u8 = null,
    file_name: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    file_type: ?[]const u8 = null,
    file_size: ?i64 = null,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var loaded = try fmus.supabase.config.loadFromEnvFileOrProcess(allocator, "..\\.env", .service);
    defer loaded.deinit();

    const client = fmus.supabase.Client.init(allocator, loaded.config);
    var query = try client.from("sidoarch__documents");
    defer query.deinit();

    _ = try query.select("id,title,file_name,file_path,file_type,file_size");
    _ = try query.orRaw("(title.ilike.*python*,content.ilike.*python*)");
    _ = try query.limit(5);

    const rows = try query.jsonParse([]DocumentRow);

    std.debug.print("table=sidoarch__documents term=python rows={d}\n", .{rows.len});
    for (rows, 0..) |row, index| {
        std.debug.print("[{d}] {s}\n", .{ index + 1, row.title orelse "(untitled)" });
        if (row.file_path) |path| std.debug.print("path={s}\n", .{path});
        if (row.file_type) |kind| std.debug.print("type={s}\n", .{kind});
        if (row.file_size) |size| std.debug.print("size={d}\n", .{size});
    }
}
