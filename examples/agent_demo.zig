const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tools = [_]fmus.tool.Def{
        .{
            .name = "read_file",
            .description = "Read a file from disk",
            .params = &.{.{
                .name = "path",
                .description = "Path to read",
            }},
        },
        .{
            .name = "grep",
            .description = "Search text inside files",
            .params = &.{
                .{ .name = "pattern", .description = "Pattern to search" },
                .{ .name = "path", .description = "Target path" },
            },
        },
    };

    const template =
        \\You are {{name}}, a practical coding assistant.
        \\Answer tersely and prefer useful code over explanation.
    ;

    const system_prompt = try fmus.prompt.render(allocator, template, &.{.{ .name = "name", .value = "FMUS Agent" }});

    const gemini_key = try fmus.env.get(allocator, "GEMINI_API_KEY");
    const openai_key = try fmus.env.get(allocator, "OPENAI_API_KEY");

    var client: fmus.llm.Client = if (gemini_key) |key|
        fmus.llm.Client.gemini(key)
    else if (openai_key) |key|
        fmus.llm.Client.openai(key)
    else
        fmus.llm.Client.gemini("missing-key");

    client = client.model("gemini-2.5-flash");

    var session = try fmus.agent.Session.init(allocator, client, .{
        .name = "demo",
        .system_prompt = system_prompt,
        .tools = &tools,
    });
    defer session.deinit();

    try session.chat.user("Give me one short Zig tip.");

    if (gemini_key == null and openai_key == null) {
        const preview = try session.preview();
        defer allocator.free(preview);
        try std.fs.File.stdout().writeAll("No LLM key found. Request preview:\n");
        try std.fs.File.stdout().writeAll(preview);
        try std.fs.File.stdout().writeAll("\n");
        return;
    }

    const reply = try client.chat(allocator, session.history());
    try std.fs.File.stdout().writeAll(reply);
    try std.fs.File.stdout().writeAll("\n");
}
