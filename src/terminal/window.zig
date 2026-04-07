const builtin = @import("builtin");
const std = @import("std");
const app_mod = @import("app.zig");
const platform = @import("../platform.zig");
const runtime_mod = @import("runtime.zig");

pub const DemoConfig = struct {
    rows: usize = 30,
    cols: usize = 110,
    title: []const u8 = "FMUS Terminal Demo",
    class_name: []const u8 = "FMUSTerminalDemoWindow",
    width: i32 = 1120,
    height: i32 = 760,
};

pub fn runDemo(allocator: std.mem.Allocator) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
    try runDefaultShellWindow(allocator, .{
        .title = "FMUS Terminal Demo",
        .class_name = "FMUSTerminalDemoWindow",
        .rows = 30,
        .cols = 110,
        .width = 1120,
        .height = 760,
    });
}

pub fn runCommandWindow(allocator: std.mem.Allocator, config: runtime_mod.Config, argv: []const []const u8) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    var runtime = try runtime_mod.Runtime.init(allocator, config);
    defer runtime.deinit();
    try runtime.spawn(argv);
    try runtime.run();
}

pub fn runDefaultShellWindow(allocator: std.mem.Allocator, config: runtime_mod.Config) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    var runtime = try runtime_mod.Runtime.init(allocator, config);
    defer runtime.deinit();
    try runtime.spawnDefaultShell();
    try runtime.run();
}

pub fn runSnapshotWindow(allocator: std.mem.Allocator, config: DemoConfig, snapshot: []const u8) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    var window = try platform.Window.init(allocator, .{
        .title = config.title,
        .class_name = config.class_name,
        .text = snapshot,
        .width = config.width,
        .height = config.height,
    });
    defer window.deinit();
    try window.run();
}

pub fn buildDemoSnapshot(allocator: std.mem.Allocator, config: DemoConfig) ![]const u8 {
    var app = try app_mod.App.open(allocator, .{
        .rows = config.rows,
        .cols = config.cols,
    });
    defer app.deinit();

    app.feedLine("\x1b[1mFMUS Terminal Window Demo\x1b[0m");
    app.feedLine("This window is rendered by reusable platform foundations inside fmus-zig.");
    app.feedLine("The example stays terse because the OS-specific surface now lives below it.");
    app.feedLine("");

    var version_result = try app.captureCommand(&.{ "zig", "version" });
    defer version_result.deinit();

    app.feedLine("");

    var where_result = try app.captureCommand(&.{ "where.exe", "zig" });
    defer where_result.deinit();

    app.feedLine("");
    app.feedLine("Next step: live PTY-backed drawing in the same window layer.");

    return try app.snapshotAlloc(allocator);
}

test "demo snapshot produces text" {
    const snapshot = try buildDemoSnapshot(std.testing.allocator, .{ .rows = 8, .cols = 60 });
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(snapshot.len != 0);
}
