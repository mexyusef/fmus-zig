const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = fmus.cli.Parser.init(&.{ "demo", "--lang=kotlin", "build" });
    parser.skipExe();

    const lang = parser.value("--lang") orelse "zig";
    const cmd_name = parser.positional() orelse "run";

    var grammar = try fmus.grammar.load(allocator,
        \\command: WORD ("-" WORD)*
        \\lang: "zig" | "kotlin" | "scala"
    );
    defer grammar.deinit();

    var root = try fmus.ast.Node.init(allocator, "demo");
    defer root.deinit(allocator);
    try root.add(allocator, try fmus.ast.Node.withText(allocator, "command", cmd_name));
    try root.add(allocator, try fmus.ast.Node.withText(allocator, "lang", lang));

    const git_branch = if (fmus.git.isRepo(allocator, "."))
        try fmus.git.currentBranch(allocator, ".")
    else
        try allocator.dupe(u8, "n/a");

    const pretty = try fmus.json.prettyAlloc(allocator, .{
        .lang = lang,
        .command = cmd_name,
        .grammar_rule = grammar.get("command"),
        .git_branch = git_branch,
        .ast_children = root.children.items.len,
    });

    try std.fs.File.stdout().writeAll(pretty);
    try std.fs.File.stdout().writeAll("\n");
}
