const std = @import("std");

pub const Role = enum {
    system,
    user,
    assistant,
    tool,

    pub fn asString(self: Role) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
        };
    }
};

pub const Message = struct {
    role: Role,
    content: []const u8,
    name: ?[]const u8 = null,

    pub fn system(content: []const u8) Message {
        return .{ .role = .system, .content = content };
    }

    pub fn user(content: []const u8) Message {
        return .{ .role = .user, .content = content };
    }

    pub fn assistant(content: []const u8) Message {
        return .{ .role = .assistant, .content = content };
    }

    pub fn tool(name: []const u8, content: []const u8) Message {
        return .{ .role = .tool, .name = name, .content = content };
    }
};

pub const JsonMessage = struct {
    role: []const u8,
    content: []const u8,
    name: ?[]const u8 = null,
};

pub fn asJson(messages: []const Message, allocator: std.mem.Allocator) ![]JsonMessage {
    const out = try allocator.alloc(JsonMessage, messages.len);
    for (messages, 0..) |msg, i| {
        out[i] = .{
            .role = msg.role.asString(),
            .content = msg.content,
            .name = msg.name,
        };
    }
    return out;
}

pub const Var = struct {
    name: []const u8,
    value: []const u8,
};

pub fn render(allocator: std.mem.Allocator, template: []const u8, vars: []const Var) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        if (i + 1 < template.len and template[i] == '{' and template[i + 1] == '{') {
            const start = i + 2;
            const end = std.mem.indexOfPos(u8, template, start, "}}") orelse {
                try out.append(allocator, template[i]);
                i += 1;
                continue;
            };
            const key = std.mem.trim(u8, template[start..end], " \t\r\n");
            var replaced = false;
            for (vars) |v| {
                if (std.mem.eql(u8, v.name, key)) {
                    try out.appendSlice(allocator, v.value);
                    replaced = true;
                    break;
                }
            }
            if (!replaced) try out.appendSlice(allocator, template[i .. end + 2]);
            i = end + 2;
            continue;
        }
        try out.append(allocator, template[i]);
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

pub const Chat = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayListUnmanaged(Message) = .empty,

    pub fn init(allocator: std.mem.Allocator) Chat {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Chat) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.content);
            if (msg.name) |name| self.allocator.free(name);
        }
        self.messages.deinit(self.allocator);
    }

    pub fn append(self: *Chat, msg: Message) !void {
        try self.messages.append(self.allocator, .{
            .role = msg.role,
            .content = try self.allocator.dupe(u8, msg.content),
            .name = if (msg.name) |name| try self.allocator.dupe(u8, name) else null,
        });
    }

    pub fn system(self: *Chat, content: []const u8) !void {
        try self.append(Message.system(content));
    }

    pub fn user(self: *Chat, content: []const u8) !void {
        try self.append(Message.user(content));
    }

    pub fn assistant(self: *Chat, content: []const u8) !void {
        try self.append(Message.assistant(content));
    }

    pub fn tool(self: *Chat, name: []const u8, content: []const u8) !void {
        try self.append(Message.tool(name, content));
    }

    pub fn items(self: *const Chat) []const Message {
        return self.messages.items;
    }
};

test "template render substitutes variables" {
    const alloc = std.testing.allocator;
    const out = try render(alloc, "Hello {{ name }}", &.{.{ .name = "name", .value = "zig" }});
    defer alloc.free(out);
    try std.testing.expectEqualStrings("Hello zig", out);
}
