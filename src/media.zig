const std = @import("std");

pub const Kind = enum {
    text,
    image,
    audio,
    video,
    file,
};

pub const Ref = struct {
    kind: Kind,
    mime: ?[]const u8 = null,
    path: ?[]const u8 = null,
    url: ?[]const u8 = null,
    name: ?[]const u8 = null,
    size_bytes: ?u64 = null,
};

pub fn fromPath(path: []const u8, mime: ?[]const u8) Ref {
    return .{ .kind = .file, .path = path, .mime = mime };
}

test "media path ref stores path" {
    const r = fromPath("demo.txt", "text/plain");
    try std.testing.expectEqualStrings("demo.txt", r.path.?);
}
