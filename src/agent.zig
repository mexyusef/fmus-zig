const std = @import("std");
const llm = @import("llm.zig");
const prompt = @import("prompt.zig");
const tool = @import("tool.zig");

pub const Config = struct {
    name: []const u8 = "agent",
    system_prompt: ?[]const u8 = null,
    tools: []const tool.Def = &.{},
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    client: llm.Client,
    config: Config,
    chat: prompt.Chat,

    pub fn init(allocator: std.mem.Allocator, client: llm.Client, config: Config) !Session {
        var session: Session = .{
            .allocator = allocator,
            .client = client,
            .config = config,
            .chat = prompt.Chat.init(allocator),
        };

        const system = try buildSystemPrompt(allocator, config);
        defer allocator.free(system);
        if (system.len > 0) try session.chat.system(system);

        return session;
    }

    pub fn deinit(self: *Session) void {
        self.chat.deinit();
    }

    pub fn history(self: *const Session) []const prompt.Message {
        return self.chat.items();
    }

    pub fn ask(self: *Session, input: []const u8) ![]u8 {
        try self.chat.user(input);
        const reply = try self.client.chat(self.allocator, self.chat.items());
        errdefer self.allocator.free(reply);
        try self.chat.assistant(reply);
        return reply;
    }

    pub fn preview(self: *Session) ![]u8 {
        return try self.client.previewChatBody(self.allocator, self.chat.items());
    }
};

pub fn buildSystemPrompt(allocator: std.mem.Allocator, config: Config) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    if (config.system_prompt) |base| {
        try out.appendSlice(allocator, base);
    }

    if (config.tools.len > 0) {
        if (out.items.len > 0) try out.appendSlice(allocator, "\n\n");
        try out.appendSlice(allocator, "Available tools:\n");
        const catalog = try tool.renderCatalog(allocator, config.tools);
        defer allocator.free(catalog);
        try out.appendSlice(allocator, catalog);
    }

    return out.toOwnedSlice(allocator);
}

test "system prompt includes tool catalog" {
    const alloc = std.testing.allocator;
    const system = try buildSystemPrompt(alloc, .{
        .system_prompt = "You are helpful.",
        .tools = &.{.{
            .name = "read_file",
            .description = "Read file content",
        }},
    });
    defer alloc.free(system);
    try std.testing.expect(std.mem.indexOf(u8, system, "read_file") != null);
}
