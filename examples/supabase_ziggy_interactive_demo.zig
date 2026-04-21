const std = @import("std");
const fmus = @import("fmus");
const ziggy = @import("ziggy");
const support = @import("supabase_ziggy_support.zig");

const Msg = ziggy.Event;

const FocusPane = enum {
    query,
    results,
    preview,
};

const SearchHit = struct {
    id: []const u8,
    title: ?[]const u8 = null,
    file_name: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    file_type: ?[]const u8 = null,
    content_preview: ?[]const u8 = null,
    content: ?[]const u8 = null,
    language: ?[]const u8 = null,
    updated_at: ?[]const u8 = null,
    file_size: ?i64 = null,
    content_hash: ?[]const u8 = null,
    category_id: ?[]const u8 = null,
    tags: ?std.json.Value = null,
    content_type: ?[]const u8 = null,
    created_by: ?[]const u8 = null,
    created_at: ?[]const u8 = null,
    last_accessed_at: ?[]const u8 = null,
    access_count: ?i64 = null,
    is_favorite: ?bool = null,
    is_public: ?bool = null,
    is_archived: ?bool = null,
    processing_status: ?[]const u8 = null,
    extraction_metadata: ?std.json.Value = null,
    search_vector: ?[]const u8 = null,
};

const Model = struct {
    config: fmus.supabase.Config,
    query: ziggy.TextInput.State,
    results_state: ziggy.List.State = .{},
    focus: FocusPane = .results,
    preview_offset: usize = 0,
    result_arena: std.heap.ArenaAllocator,
    hits: []SearchHit = &.{},
    labels: [][]const u8 = &.{},
    preview_offsets: []usize = &.{},
    status: []const u8 = "Enter runs search. Arrow keys move focus. Esc quits.",
    last_error: ?[]const u8 = null,

    pub fn init(self: *@This(), ctx: *ziggy.Context) ziggy.Command(Msg) {
        self.performSearch(ctx.persistent_allocator) catch |err| {
            self.last_error = @errorName(err);
        };
        ctx.requestRedraw();
        return .none;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.query.deinit(allocator);
        self.result_arena.deinit();
    }

    pub fn update(self: *@This(), event: Msg, ctx: *ziggy.Context) ziggy.Command(Msg) {
        switch (event) {
            .key => |key| switch (key) {
                .ctrl_c, .escape => return .quit,
                .tab => {
                    self.focus = switch (self.focus) {
                        .query => .results,
                        .results => .preview,
                        .preview => .query,
                    };
                    ctx.requestRedraw();
                },
                .back_tab => {
                    self.focus = switch (self.focus) {
                        .query => .preview,
                        .results => .query,
                        .preview => .results,
                    };
                    ctx.requestRedraw();
                },
                .up, .down, .page_up, .page_down, .home, .end => {
                    switch (self.focus) {
                        .results => {
                            if (self.labels.len > 0) {
                                _ = ziggy.List.handleEvent(&self.results_state, self.labels, key);
                                self.syncPreviewOffsetFromSelection();
                                ctx.requestRedraw();
                            }
                        },
                        .preview => {
                            self.scrollPreview(key);
                            ctx.requestRedraw();
                        },
                        .query => {},
                    }
                },
                .enter => {
                    switch (self.focus) {
                        .query => {
                            self.performSearch(ctx.persistent_allocator) catch |err| {
                                self.last_error = @errorName(err);
                            };
                            self.syncPreviewOffsetFromSelection();
                            ctx.requestRedraw();
                        },
                        .results => {
                            self.focus = .preview;
                            ctx.requestRedraw();
                        },
                        .preview => {},
                    }
                },
                else => {
                    switch (self.focus) {
                        .query => {
                            const response = self.query.handleEvent(ctx.persistent_allocator, key) catch return .none;
                            if (response.redraw) ctx.requestRedraw();
                        },
                        .results => switch (key) {
                            .char => |c| {
                                switch (c) {
                                    'j', 'J' => {
                                        if (self.labels.len > 0) {
                                            _ = ziggy.List.handleEvent(&self.results_state, self.labels, .down);
                                            self.syncPreviewOffsetFromSelection();
                                            ctx.requestRedraw();
                                        }
                                    },
                                    'k', 'K' => {
                                        if (self.labels.len > 0) {
                                            _ = ziggy.List.handleEvent(&self.results_state, self.labels, .up);
                                            self.syncPreviewOffsetFromSelection();
                                            ctx.requestRedraw();
                                        }
                                    },
                                    else => {},
                                }
                            },
                            else => {},
                        },
                        .preview => switch (key) {
                            .char => |c| {
                                switch (c) {
                                    'j', 'J' => {
                                        self.scrollPreview(.down);
                                        ctx.requestRedraw();
                                    },
                                    'k', 'K' => {
                                        self.scrollPreview(.up);
                                        ctx.requestRedraw();
                                    },
                                    else => {},
                                }
                            },
                            else => {},
                        },
                    }
                },
            },
            else => {},
        }
        return .none;
    }

    fn performSearch(self: *@This(), allocator: std.mem.Allocator) !void {
        self.result_arena.deinit();
        self.result_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const search_allocator = self.result_arena.allocator();
        const client = fmus.supabase.Client.init(search_allocator, self.config);
        const term = if (self.query.editor.value.len == 0) "python" else self.query.editor.value;

        self.hits = try client.rest.rpcParse([]SearchHit, "search_documents", .{
            .search_query = term,
            .search_limit = 8,
            .search_in_title = true,
            .search_in_content = true,
        });

        self.labels = try search_allocator.alloc([]const u8, self.hits.len);
        self.preview_offsets = try search_allocator.alloc(usize, self.hits.len);
        @memset(self.preview_offsets, 0);
        for (self.hits, 0..) |hit, index| {
            self.labels[index] = try std.fmt.allocPrint(search_allocator, "{d}. {s}", .{
                index + 1,
                hit.title orelse hit.file_name orelse "(untitled)",
            });
        }

        if (self.hits.len == 0) {
            self.results_state.selection.cursor = 0;
            self.status = "No matches returned.";
        } else {
            if (self.results_state.selection.cursor >= self.hits.len) {
                self.results_state.selection.cursor = 0;
            }
            self.results_state.selection.focused = true;
            self.syncPreviewOffsetFromSelection();
            self.status = try std.fmt.allocPrint(allocator, "query={s} hits={d}", .{ term, self.hits.len });
        }
        self.last_error = null;
    }

    fn scrollPreview(self: *@This(), key: ziggy.Key) void {
        if (self.hits.len == 0) return;
        switch (key) {
            .up => self.preview_offset -|= 1,
            .down => self.preview_offset += 1,
            .page_up => self.preview_offset -|= 8,
            .page_down => self.preview_offset += 8,
            .home => self.preview_offset = 0,
            else => {},
        }
        self.storePreviewOffsetForSelection();
    }

    fn selectionIndex(self: *@This()) usize {
        if (self.hits.len == 0) return 0;
        return @min(self.results_state.selection.cursor, self.hits.len - 1);
    }

    fn storePreviewOffsetForSelection(self: *@This()) void {
        if (self.preview_offsets.len == 0) return;
        self.preview_offsets[self.selectionIndex()] = self.preview_offset;
    }

    fn syncPreviewOffsetFromSelection(self: *@This()) void {
        if (self.preview_offsets.len == 0) {
            self.preview_offset = 0;
            return;
        }
        self.preview_offset = self.preview_offsets[self.selectionIndex()];
    }

    pub fn viewNode(self: *@This(), ctx: *ziggy.Context) !*const ziggy.Node {
        const theme = ziggy.defaultAgentTheme();

        const header = try ziggy.HeaderBar.build(ctx.allocator, "Supabase Interactive Search", .{
            .subtitle = self.config.url,
            .right_text = "Tab next | Shift+Tab prev | Esc quit",
            .style = theme.pane,
            .title_style = theme.pane_active,
            .subtitle_style = theme.status_idle,
            .right_style = theme.selected_alt,
            .border_style = theme.border_style,
        });

        self.query.prompt = "search> ";
        self.query.focused = self.focus == .query;
        self.query.style = if (self.focus == .query) theme.selected_alt else theme.pane;
        self.query.placeholder = "Type a search term";
        const query_node = try self.query.buildNode(ctx.allocator);
        const query_help = try ziggy.Text.buildWithOptions(ctx.allocator, controlsText(self.focus), .{
            .style = if (self.focus == .query) theme.selected_alt else theme.status_idle,
            .wrap = .truncate_end,
        });
        const query_stack = try ziggy.VStack.build(ctx.allocator, &.{ query_node, query_help }, 1);
        const query_box = try ziggy.Box.buildWithOptions(ctx.allocator, titleForPane("Query", self.focus == .query), query_stack, .{
            .style = if (self.focus == .query) theme.selected_alt else theme.pane,
            .border_style = theme.border_style,
            .padding_left = 1,
            .padding_right = 1,
            .padding_top = 1,
            .padding_bottom = 1,
        });

        const results_child = if (self.labels.len == 0)
            try ziggy.Text.buildWithOptions(ctx.allocator, self.last_error orelse "No results yet.", .{
                .style = theme.status_idle,
                .wrap = .wrap,
            })
        else
            try ziggy.List.buildState(ctx.allocator, self.labels, self.results_state, .{
                .style = theme.pane,
                .selected_style = theme.selected_alt,
                .focus = .{ .active = self.focus == .results, .focus_id = "results" },
            });
        const results_box = try ziggy.Box.buildWithOptions(ctx.allocator, titleForPane("Results", self.focus == .results), results_child, .{
            .style = if (self.focus == .results) theme.selected_alt else theme.pane,
            .border_style = theme.border_style,
            .padding_left = 1,
            .padding_right = 1,
            .padding_top = 1,
            .padding_bottom = 1,
        });

        const preview_lines = try self.previewLinesAlloc(ctx.allocator);
        const preview_doc = try ziggy.Document.build(ctx.allocator, preview_lines, self.preview_offset, if (self.focus == .preview) theme.selected_alt else theme.status_idle);
        const preview_box = try ziggy.Box.buildWithOptions(ctx.allocator, titleForPane("Preview", self.focus == .preview), preview_doc, .{
            .style = if (self.focus == .preview) theme.selected_alt else theme.pane,
            .border_style = theme.border_style,
            .padding_left = 1,
            .padding_right = 1,
            .padding_top = 1,
            .padding_bottom = 1,
        });

        const body = try ziggy.HStack.buildWithWeights(ctx.allocator, &.{ results_box, preview_box }, 1, &.{ 4, 5 });

        const footer = try ziggy.FooterBar.build(ctx.allocator, "interactive", "live Supabase", .{
            .center = self.last_error orelse try std.fmt.allocPrint(ctx.allocator, "{s} | focus={s} | Tab cycles panes", .{
                self.status,
                @tagName(self.focus),
            }),
            .style = theme.pane,
            .left_style = theme.selected_alt,
            .center_style = if (self.last_error == null) theme.status_idle else theme.selected_alt,
            .right_style = theme.status_idle,
            .border_style = theme.border_style,
        });

        return try ziggy.VStack.buildWithWeights(ctx.allocator, &.{ header, query_box, body, footer }, 1, &.{ 0, 0, 1, 0 });
    }

    fn previewTextAlloc(self: *@This(), allocator: std.mem.Allocator) ![]const u8 {
        if (self.hits.len == 0) {
            return try allocator.dupe(u8, "Run a search to load Supabase document results.");
        }

        const index = @min(self.results_state.selection.cursor, self.hits.len - 1);
        const hit = self.hits[index];
        const preview = hit.content_preview orelse hit.content orelse "No preview available.";
        const snippet = if (preview.len > 900) preview[0..900] else preview;
        return try std.fmt.allocPrint(allocator,
            \\title: {s}
            \\type: {s}
            \\language: {s}
            \\updated: {s}
            \\path: {s}
            \\
            \\controls:
            \\  Tab / Shift+Tab: change pane
            \\  j/k or arrows: move/scroll in focused pane
            \\  Enter in Query: run search
            \\
            \\{s}
        , .{
            hit.title orelse hit.file_name orelse "(untitled)",
            hit.file_type orelse "-",
            hit.language orelse "-",
            compactTimestamp(hit.updated_at orelse "-"),
            hit.file_path orelse "-",
            snippet,
        });
    }

    fn previewLinesAlloc(self: *@This(), allocator: std.mem.Allocator) ![]const []const u8 {
        const text = try self.previewTextAlloc(allocator);
        var count: usize = 1;
        for (text) |char| {
            if (char == '\n') count += 1;
        }
        const lines = try allocator.alloc([]const u8, count);
        var iter = std.mem.splitScalar(u8, text, '\n');
        var index: usize = 0;
        while (iter.next()) |line| : (index += 1) {
            lines[index] = line;
        }
        return lines[0..index];
    }
};

fn titleForPane(base: []const u8, active: bool) []const u8 {
    return if (active)
        switch (base[0]) {
            'Q' => "[Active] Query",
            'R' => "[Active] Results",
            'P' => "[Active] Preview",
            else => base,
        }
    else
        base;
}

fn controlsText(focus: FocusPane) []const u8 {
    return switch (focus) {
        .query => "Active pane. Enter searches. Tab moves to Results. Shift+Tab moves to Preview.",
        .results => "Active pane. Up/Down or j/k moves hits. Enter jumps to Preview. Tab moves on.",
        .preview => "Active pane. Up/Down/Page keys or j/k scroll preview. Shift+Tab goes back.",
    };
}

fn compactTimestamp(value: []const u8) []const u8 {
    return if (value.len >= 10) value[0..10] else value;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var loaded = try fmus.supabase.config.loadFromEnvFileOrProcess(allocator, "..\\.env", .service);
    defer loaded.deinit();

    const query = try ziggy.TextInput.State.init(allocator, "python");
    const model: Model = .{
        .config = loaded.config,
        .query = query,
        .result_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
    };
    var owned_model = model;
    defer owned_model.deinit(allocator);

    try support.runInteractiveProgram(Model, Msg, allocator, owned_model, .{
        .title = "supabase ziggy interactive",
        .tick_interval_ms = 0,
    });
}
