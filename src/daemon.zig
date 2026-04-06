const std = @import("std");
const fs = @import("fs.zig");
const time = @import("time.zig");

pub const Spec = struct {
    name: []const u8,
    pid_path: []const u8,
};

pub fn writePid(spec: Spec) !void {
    const allocator = std.heap.page_allocator;
    const out = try std.fmt.allocPrint(allocator, "{d}\n", .{time.nowMs()});
    defer allocator.free(out);
    try fs.writeText(spec.pid_path, out);
}

pub fn clearPid(spec: Spec) void {
    fs.remove(spec.pid_path) catch {};
}

pub fn isRunning(spec: Spec) bool {
    return fs.exists(spec.pid_path);
}

test "daemon running reflects pid file" {
    const spec: Spec = .{ .name = "demo", .pid_path = "__fmus_daemon.pid" };
    defer clearPid(spec);
    try writePid(spec);
    try std.testing.expect(isRunning(spec));
}
