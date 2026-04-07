const std = @import("std");

var mutex: std.Thread.Mutex = .{};

fn path() []const u8 {
    return "C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\terminal-deep-debug.log";
}

pub fn reset() void {
    mutex.lock();
    defer mutex.unlock();
    const file = std.fs.createFileAbsolute(path(), .{ .truncate = true }) catch return;
    file.close();
}

pub fn log(comptime fmt: []const u8, args: anytype) void {
    mutex.lock();
    defer mutex.unlock();
    const file = openAppendFile() orelse return;
    defer file.close();
    var buf: [1024]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, fmt, args) catch return;
    file.writeAll(line) catch return;
    file.writeAll("\n") catch return;
}

pub fn logBytes(label: []const u8, bytes: []const u8) void {
    mutex.lock();
    defer mutex.unlock();
    const file = openAppendFile() orelse return;
    defer file.close();
    file.writeAll(label) catch return;
    file.writeAll(":") catch return;
    for (bytes) |byte| {
        var hex: [4]u8 = undefined;
        const part = std.fmt.bufPrint(&hex, " {x:0>2}", .{byte}) catch return;
        file.writeAll(part) catch return;
    }
    file.writeAll("\n") catch return;
}

fn openAppendFile() ?std.fs.File {
    if (std.fs.openFileAbsolute(path(), .{ .mode = .write_only })) |file| {
        file.seekFromEnd(0) catch {};
        return file;
    } else |_| {
        const file = std.fs.createFileAbsolute(path(), .{ .truncate = false }) catch return null;
        file.seekFromEnd(0) catch {};
        return file;
    }
}
