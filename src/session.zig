const std = @import("std");
const fs = @import("fs.zig");
const id = @import("id.zig");
const json = @import("json.zig");
const prompt = @import("prompt.zig");
const time = @import("time.zig");

pub const Summary = struct {
    id: []const u8,
    title: []const u8,
    created_ms: i64,
    updated_ms: i64,
    message_count: usize,
};

pub const Doc = struct {
    id: []const u8,
    title: []const u8,
    created_ms: i64,
    updated_ms: i64,
    messages: []const prompt.JsonMessage,
};

pub fn toJsonMessages(allocator: std.mem.Allocator, messages: []const prompt.Message) ![]prompt.JsonMessage {
    return try prompt.asJson(messages, allocator);
}

pub fn save(allocator: std.mem.Allocator, path: []const u8, title: []const u8, messages: []const prompt.Message) ![]u8 {
    const sid = try id.stamped(allocator, "session");
    const json_messages = try toJsonMessages(allocator, messages);
    const now = time.nowMs();
    try fs.writeJson(path, Doc{
        .id = sid,
        .title = title,
        .created_ms = now,
        .updated_ms = now,
        .messages = json_messages,
    });
    return sid;
}

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Doc {
    return try json.parseFile(allocator, Doc, path);
}

pub fn summarize(doc: Doc) Summary {
    return .{
        .id = doc.id,
        .title = doc.title,
        .created_ms = doc.created_ms,
        .updated_ms = doc.updated_ms,
        .message_count = doc.messages.len,
    };
}

pub fn pruneCount(allocator: std.mem.Allocator, messages: []const prompt.Message, keep_last: usize) ![]prompt.JsonMessage {
    const start = if (messages.len > keep_last) messages.len - keep_last else 0;
    return try prompt.asJson(messages[start..], allocator);
}

test "session summary counts messages" {
    const doc = Doc{
        .id = "s1",
        .title = "demo",
        .created_ms = 1,
        .updated_ms = 2,
        .messages = &.{ .{ .role = "user", .content = "hello", .name = null } },
    };
    const summary = summarize(doc);
    try std.testing.expectEqual(@as(usize, 1), summary.message_count);
}
