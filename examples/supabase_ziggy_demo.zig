const std = @import("std");
const fmus = @import("fmus");
const ziggy = @import("ziggy");

const SearchHit = struct {
    id: []const u8,
    title: ?[]const u8 = null,
    file_name: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    file_type: ?[]const u8 = null,
    file_size: ?i64 = null,
    content_hash: ?[]const u8 = null,
    content_preview: ?[]const u8 = null,
    content: ?[]const u8 = null,
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
    _ = ziggy.prepareConsole();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const term = try readSearchTerm(allocator);
    var loaded = try fmus.supabase.config.loadFromEnvFileOrProcess(allocator, "..\\.env", .service);
    defer loaded.deinit();

    const client = fmus.supabase.Client.init(allocator, loaded.config);
    const hits = try client.rest.rpcParse([]SearchHit, "search_documents", .{
        .search_query = term,
        .search_limit = 6,
        .search_in_title = true,
        .search_in_content = true,
    });

    const root = try buildScreen(allocator, loaded.config.url, term, hits);
    const output = try ziggy.renderToString(allocator, root, .{
        .width = 118,
        .height = 42,
        .ansi_styles = true,
        .trim_trailing_spaces = false,
        .include_final_newline = true,
    });
    defer allocator.free(output);

    try ziggy.writeStdout(allocator, output);
}

fn readSearchTerm(allocator: std.mem.Allocator) ![]const u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    if (args.next()) |term| {
        return try allocator.dupe(u8, term);
    }
    return try allocator.dupe(u8, "python");
}

fn buildScreen(
    allocator: std.mem.Allocator,
    project_url: []const u8,
    term: []const u8,
    hits: []const SearchHit,
) !*const ziggy.Node {
    const theme = ziggy.defaultAgentTheme();

    const header = try ziggy.Card.build(allocator, "Supabase Document Search", .{
        .subtitle = "fmus-zig + ziggy local dependency example",
        .body = "Live Supabase search rendered through ziggy with the corrected Windows output path.",
        .style = theme.pane,
        .title_style = theme.pane_active,
        .subtitle_style = theme.status_idle,
        .body_style = theme.status_idle,
        .border_style = theme.border_style,
    });

    const summary = try std.fmt.allocPrint(allocator, "query={s}  hits={d}  source={s}", .{
        term,
        hits.len,
        project_url,
    });
    const summary_bar = try ziggy.Text.buildWithOptions(allocator, summary, .{
        .style = theme.status_idle,
        .wrap = .truncate_end,
    });

    const command_panel = try buildCommandPanel(allocator, theme, term);
    const table_panel = try buildResultsPanel(allocator, theme, hits);
    const preview_panel = try buildPreviewPanel(allocator, theme, hits);
    const content = try ziggy.HStack.buildWithWeights(allocator, &.{ table_panel, preview_panel }, 1, &.{ 5, 4 });
    const body = try ziggy.VStack.buildWithWeights(allocator, &.{ command_panel, content }, 1, &.{ 2, 5 });

    const footer = try ziggy.Text.buildWithOptions(allocator,
        "search_documents | next step: convert this static screen into a ziggy.Program search workflow | term arg supported",
        .{
            .style = theme.status_idle,
            .wrap = .truncate_end,
        },
    );

    return try ziggy.VStack.buildWithWeights(allocator, &.{ header, summary_bar, body, footer }, 1, &.{ 3, 1, 7, 1 });
}

fn buildPanel(
    allocator: std.mem.Allocator,
    title: []const u8,
    body: []const u8,
    theme: ziggy.AgentTheme,
) !*const ziggy.Node {
    const text = try ziggy.Text.buildWithOptions(allocator, body, .{
        .style = theme.status_idle,
        .wrap = .wrap,
    });
    return try ziggy.Box.buildWithOptions(allocator, title, text, .{
        .style = theme.pane,
        .border_style = theme.border_style,
        .padding_left = 1,
        .padding_right = 1,
        .padding_top = 1,
        .padding_bottom = 1,
    });
}

fn buildCommandPanel(
    allocator: std.mem.Allocator,
    theme: ziggy.AgentTheme,
    term: []const u8,
) !*const ziggy.Node {
    const body = try std.fmt.allocPrint(allocator,
        \\query: {s}
        \\mode: rpc search_documents
        \\future actions:
        \\  1. Search Documents
        \\  2. Open Focused Preview
        \\  3. Keepalive Status
        \\  4. Browse Storage Buckets
    , .{term});
    return try buildPanel(allocator, "Query Flow", body, theme);
}

fn buildResultsPanel(
    allocator: std.mem.Allocator,
    theme: ziggy.AgentTheme,
    hits: []const SearchHit,
) !*const ziggy.Node {
    var lines = std.ArrayList(u8).empty;
    const writer = lines.writer(allocator);
    try writer.writeAll("Title | Type | Lang | Updated\n");
    try writer.writeAll("--------------------------------\n");
    for (hits, 0..) |hit, index| {
        const title = hit.title orelse hit.file_name orelse "(untitled)";
        try writer.print("{d}. {s}\n", .{ index + 1, title });
        try writer.print("   type={s} lang={s} updated={s}\n", .{
            hit.file_type orelse "-",
            hit.language orelse "-",
            compactTimestamp(hit.updated_at orelse "-"),
        });
    }
    const body = try lines.toOwnedSlice(allocator);
    return try buildPanel(allocator, "Results", body, theme);
}

fn buildPreviewPanel(
    allocator: std.mem.Allocator,
    theme: ziggy.AgentTheme,
    hits: []const SearchHit,
) !*const ziggy.Node {
    if (hits.len == 0) {
        return try buildPanel(allocator, "Preview", "search_documents returned zero rows.\nChange the search term argument to inspect other documents from Supabase.", theme);
    }

    const first = hits[0];
    const title = first.title orelse first.file_name orelse "(untitled)";
    const path = first.file_path orelse "(no path)";
    const meta = try std.fmt.allocPrint(allocator, "type={s}  lang={s}  updated={s}", .{
        first.file_type orelse "-",
        first.language orelse "-",
        compactTimestamp(first.updated_at orelse "-"),
    });
    const preview_source = first.content_preview orelse first.content orelse "No preview available.";
    const preview = normalizePreview(allocator, preview_source, 520);
    const body = try std.fmt.allocPrint(allocator,
        \\title: {s}
        \\{s}
        \\path: {s}
        \\
        \\preview:
        \\{s}
    , .{ title, meta, path, preview });
    return try buildPanel(allocator, "Preview", body, theme);
}

fn compactTimestamp(value: []const u8) []const u8 {
    return if (value.len >= 10) value[0..10] else value;
}

fn normalizePreview(allocator: std.mem.Allocator, value: []const u8, max_len: usize) []const u8 {
    const clipped = if (value.len > max_len) value[0..max_len] else value;
    const buffer = allocator.alloc(u8, clipped.len) catch return clipped;
    for (clipped, 0..) |char, index| {
        buffer[index] = switch (char) {
            '\n', '\r', '\t' => ' ',
            else => char,
        };
    }
    return buffer;
}
