const std = @import("std");
const fmus = @import("src/fmus.zig");

const SearchHit = struct {
    id: []const u8,
    title: ?[]const u8 = null,
    file_name: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    file_type: ?[]const u8 = null,
    file_size: ?i64 = null,
    content_hash: ?[]const u8 = null,
    content: ?[]const u8 = null,
    content_preview: ?[]const u8 = null,
    category_id: ?[]const u8 = null,
    tags: ?std.json.Value = null,
    language: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
    created_by: ?[]const u8 = null,
    created_at: ?[]const u8 = null,
    updated_at: ?[]const u8 = null,
    last_accessed_at: ?[]const u8 = null,
    access_count: ?i64 = null,
    is_favorite: ?bool = null,
    is_public: ?bool = null,
    is_archived: ?bool = null,
    processing_status: ?[]const u8 = null,
    extraction_metadata: ?std.json.Value = null,
    search_vector: ?[]const u8 = null,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var loaded = try fmus.supabase.config.loadFromEnvFileOrProcess(allocator, "..\\.env", .service);
    defer loaded.deinit();

    const client = fmus.supabase.Client.init(allocator, loaded.config);
    const hits = try client.rest.rpcParse([]SearchHit, "search_documents", .{
        .search_query = "python",
        .search_limit = 5,
        .search_in_title = true,
        .search_in_content = true,
    });

    std.debug.print("search_query=python\n", .{});
    std.debug.print("hits={d}\n", .{hits.len});
    for (hits, 0..) |hit, index| {
        std.debug.print("[{d}] {s}\n", .{ index + 1, hit.title orelse "(untitled)" });
        if (hit.file_path) |path| std.debug.print("path={s}\n", .{path});
        if (hit.file_type) |kind| std.debug.print("type={s}\n", .{kind});
        if (hit.content_preview) |preview| {
            const snippet = if (preview.len > 140) preview[0..140] else preview;
            std.debug.print("preview={s}\n", .{snippet});
        } else if (hit.content) |content| {
            const snippet = if (content.len > 140) content[0..140] else content;
            std.debug.print("snippet={s}\n", .{snippet});
        }
    }
}
