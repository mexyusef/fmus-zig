const builtin = @import("builtin");
const std = @import("std");
const command_mod = @import("command.zig");
const pane_mod = @import("pane.zig");
const view_mod = @import("view.zig");
const proc = @import("../proc.zig");

pub const Config = struct {
    rows: usize = 24,
    cols: usize = 80,
    cwd: ?[]const u8 = null,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    pane: pane_mod.Pane,

    pub fn init(allocator: std.mem.Allocator, config: Config) !App {
        return .{
            .allocator = allocator,
            .pane = try pane_mod.Pane.init(allocator, .{
                .rows = config.rows,
                .cols = config.cols,
                .cwd = config.cwd,
            }),
        };
    }

    pub fn open(allocator: std.mem.Allocator, config: Config) !App {
        return init(allocator, config);
    }

    pub fn deinit(self: *App) void {
        self.pane.deinit();
    }

    pub fn feed(self: *App, bytes: []const u8) void {
        self.pane.feed(bytes);
    }

    pub fn feedLine(self: *App, line: []const u8) void {
        self.pane.feedLine(line);
    }

    pub fn spawn(self: *App, argv: []const []const u8) !void {
        try self.pane.spawn(argv);
    }

    pub fn pollOnce(self: *App) !usize {
        return self.pane.pollOnce();
    }

    pub fn sendInput(self: *App, bytes: []const u8) !void {
        try self.pane.sendInput(bytes);
    }

    pub fn childExited(self: *const App) bool {
        return self.pane.childExited();
    }

    pub fn captureCommand(self: *App, argv: []const []const u8) !proc.Result {
        const result = try proc.cmd(argv).run(self.allocator);
        self.feed(result.stdout);
        if (result.stderr.len > 0) {
            if (result.stdout.len > 0 and result.stdout[result.stdout.len - 1] != '\n') self.feed("\r\n");
            self.feed(result.stderr);
        }
        return result;
    }

    pub fn runToEnd(self: *App, argv: []const []const u8) !pane_mod.RunResult {
        return self.pane.runToEnd(argv, null);
    }

    pub fn runShellCommand(self: *App, command: []const u8) !pane_mod.RunResult {
        var shell = try command_mod.shellCommandAlloc(self.allocator, command);
        defer shell.deinit();
        return self.runToEnd(shell.argv);
    }

    pub fn snapshotAlloc(self: *const App, allocator: std.mem.Allocator) ![]u8 {
        return self.pane.snapshotAlloc(allocator);
    }

    pub fn renderText(self: *const App, writer: anytype) !void {
        try self.pane.renderText(writer);
    }

    pub fn screen(self: *const App) view_mod.ScreenView {
        return self.pane.screen();
    }
};

test "app runs a command into terminal state" {
    var app = try App.init(std.testing.allocator, .{ .rows = 4, .cols = 32 });
    defer app.deinit();

    var result = try app.runToEnd(&.{ "zig", "version" });
    defer result.deinit(std.testing.allocator);

    const snapshot = try app.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(snapshot.len != 0);
}

test "app exposes shell command helper on windows only" {
    if (builtin.os.tag != .windows) return;

    var app = try App.init(std.testing.allocator, .{ .rows = 6, .cols = 48 });
    defer app.deinit();

    var result = try app.runShellCommand("echo hello from fmus");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.term == .Exited);
}

test "app captures direct process output" {
    var app = try App.init(std.testing.allocator, .{ .rows = 6, .cols = 48 });
    defer app.deinit();

    var result = try app.captureCommand(&.{ "zig", "version" });
    defer result.deinit();

    const snapshot = try app.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "0.15") != null);
}
