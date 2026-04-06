const std = @import("std");
const http = @import("http.zig");
const json = @import("json.zig");
const prompt = @import("prompt.zig");

pub const Provider = enum {
    openai_compatible,
    gemini,
};

pub const Client = struct {
    provider: Provider,
    api_key: []const u8,
    model_name: []const u8,
    base_url: ?[]const u8 = null,

    pub fn openai(api_key: []const u8) Client {
        return .{
            .provider = .openai_compatible,
            .api_key = api_key,
            .model_name = "gpt-4.1-mini",
        };
    }

    pub fn gemini(api_key: []const u8) Client {
        return .{
            .provider = .gemini,
            .api_key = api_key,
            .model_name = "gemini-2.5-flash",
        };
    }

    pub fn compatible(api_key: []const u8, base_url: []const u8) Client {
        return .{
            .provider = .openai_compatible,
            .api_key = api_key,
            .model_name = "gpt-4.1-mini",
            .base_url = base_url,
        };
    }

    pub fn model(self: Client, model_name: []const u8) Client {
        var next = self;
        next.model_name = model_name;
        return next;
    }

    pub fn endpoint(self: Client) []const u8 {
        return self.base_url orelse switch (self.provider) {
            .openai_compatible => "https://api.openai.com/v1/chat/completions",
            .gemini => "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        };
    }

    fn authHeader(self: Client, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
    }

    pub fn previewChatBody(self: Client, allocator: std.mem.Allocator, messages: []const prompt.Message) ![]u8 {
        const JsonBody = struct {
            model: []const u8,
            messages: []const prompt.JsonMessage,
        };

        const msgs = try prompt.asJson(messages, allocator);
        defer allocator.free(msgs);

        return try json.prettyAlloc(allocator, JsonBody{
            .model = self.model_name,
            .messages = msgs,
        });
    }

    pub fn chat(self: Client, allocator: std.mem.Allocator, messages: []const prompt.Message) ![]u8 {
        const JsonBody = struct {
            model: []const u8,
            messages: []const prompt.JsonMessage,
        };
        const JsonResponse = struct {
            choices: []const struct {
                message: struct {
                    content: ?[]const u8 = null,
                },
            } = &.{},
            @"error": ?struct {
                message: ?[]const u8 = null,
            } = null,
        };

        const msgs = try prompt.asJson(messages, allocator);
        defer allocator.free(msgs);

        const body = try json.stringifyAlloc(allocator, JsonBody{
            .model = self.model_name,
            .messages = msgs,
        });
        defer allocator.free(body);

        const auth = try self.authHeader(allocator);
        defer allocator.free(auth);

        const headers = [_]http.Header{
            .{ .name = "authorization", .value = auth },
            .{ .name = "accept", .value = "application/json" },
        };

        var response = try http.post(self.endpoint()).header(&headers).body(body, "application/json").send(allocator);
        defer response.deinit();

        const parsed = try json.parse(allocator, JsonResponse, response.body);
        if (parsed.@"error") |provider_err| {
            if (provider_err.message) |message| {
                return try allocator.dupe(u8, message);
            }
            return error.ProviderRequestFailed;
        }

        if (parsed.choices.len == 0) return error.EmptyChoice;
        const content = parsed.choices[0].message.content orelse return error.EmptyChoice;
        return try allocator.dupe(u8, content);
    }

    pub fn ask(self: Client, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        return try self.chat(allocator, &.{prompt.Message.user(input)});
    }
};

test "preview chat body includes model and content" {
    const alloc = std.testing.allocator;
    const out = try Client.gemini("key").previewChatBody(alloc, &.{prompt.Message.user("hello")});
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "gemini-2.5-flash") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "hello") != null);
}
