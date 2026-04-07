const std = @import("std");
const engine_mod = @import("engine.zig");
const pty_mod = @import("pty.zig");
const snapshot_mod = @import("snapshot.zig");
const text_render = @import("text_render.zig");
const view_mod = @import("view.zig");
const action_mod = @import("action.zig");
const key_encode = @import("key_encode.zig");
const debug_mod = @import("debug.zig");

pub const Config = struct {
    rows: usize = 24,
    cols: usize = 80,
    cwd: ?[]const u8 = null,
};

pub const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    pub fn deinit(self: *RunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

pub const Pane = struct {
    allocator: std.mem.Allocator,
    engine: engine_mod.Engine,
    pty: ?pty_mod.Pty = null,
    cwd: ?[]const u8 = null,
    shell_type: pty_mod.ShellType = .auto,

    pub fn init(allocator: std.mem.Allocator, config: Config) !Pane {
        return .{
            .allocator = allocator,
            .engine = try engine_mod.Engine.init(allocator, config.rows, config.cols),
            .cwd = config.cwd,
        };
    }

    pub fn deinit(self: *Pane) void {
        if (self.pty) |*pty| pty.deinit();
        self.engine.deinit();
    }

    pub fn resize(self: *Pane, rows: usize, cols: usize) !void {
        const existing = self.pty != null;
        if (existing) {
            if (self.pty) |*pty| try pty.resize(@intCast(rows), @intCast(cols));
        }
        try self.engine.resize(rows, cols);
    }

    pub fn feed(self: *Pane, bytes: []const u8) void {
        self.processIncoming(bytes) catch self.engine.feed(bytes);
    }

    pub fn feedLine(self: *Pane, line: []const u8) void {
        self.feed(line);
        self.feed("\r\n");
    }

    pub fn spawn(self: *Pane, argv: []const []const u8) !void {
        if (self.pty) |*existing| existing.deinit();
        self.shell_type = pty_mod.ShellType.detect(argv);
        self.pty = try pty_mod.Pty.spawn(self.allocator, .{
            .argv = argv,
            .cwd = self.cwd,
            .rows = @intCast(self.engine.state.rowCount()),
            .cols = @intCast(self.engine.state.colCount()),
            .shell = self.shell_type,
        });
    }

    pub fn shellType(self: *const Pane) pty_mod.ShellType {
        return self.shell_type;
    }

    pub fn pollOnce(self: *Pane) !usize {
        const pty = if (self.pty) |*pty| pty else return 0;
        const maybe_chunk = try pty.readAvailable(self.allocator);
        if (maybe_chunk) |chunk| {
            defer if (chunk.owned) self.allocator.free(chunk.bytes);
            try self.processIncoming(chunk.bytes);
            return chunk.bytes.len;
        }
        return 0;
    }

    pub fn sendInput(self: *Pane, bytes: []const u8) !void {
        const pty = if (self.pty) |*pty| pty else return error.NoProcess;
        try pty.writeAll(bytes);
    }

    pub fn sendKey(self: *Pane, event: key_encode.KeyEvent) !void {
        var out: [128]u8 = undefined;
        const bytes = key_encode.encodeKey(event, .{
            .cursor_keys_app = self.engine.state.cursor_keys_app,
            .keypad_app_mode = self.engine.state.keypad_app_mode,
            .kitty_flags = self.engine.state.kittyFlags(),
        }, &out);
        if (bytes.len == 0) return;
        try self.sendInput(bytes);
    }

    pub fn childExited(self: *Pane) bool {
        const pty = if (self.pty) |*pty| pty else return true;
        return pty.childExited();
    }

    pub fn ptyExitCode(self: *Pane) ?u8 {
        const pty = if (self.pty) |*pty| pty else return null;
        return pty.exitCode();
    }

    pub fn runToEnd(self: *Pane, argv: []const []const u8, cwd: ?[]const u8) !RunResult {
        if (cwd != null) self.cwd = cwd;
        try self.spawn(argv);

        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        var exit_seen = false;
        var exit_idle_polls: usize = 0;

        while (true) {
            const pty = if (self.pty) |*pty| pty else break;
            if (try pty.readAvailable(self.allocator)) |chunk| {
                defer if (chunk.owned) self.allocator.free(chunk.bytes);
                try out.appendSlice(self.allocator, chunk.bytes);
                try self.processIncoming(chunk.bytes);
                if (exit_seen) exit_idle_polls = 0;
                continue;
            }

            if (pty.childExited()) {
                exit_seen = true;
                exit_idle_polls += 1;
                if (exit_idle_polls >= 8) break;
            }
            std.Thread.sleep(15 * std.time.ns_per_ms);
        }

        const pty = if (self.pty) |*pty| pty else return error.NoProcess;
        pty.wait();
        const code = pty.exitCode() orelse 1;

        return .{
            .stdout = try out.toOwnedSlice(self.allocator),
            .stderr = try self.allocator.dupe(u8, ""),
            .term = .{ .Exited = code },
        };
    }

    pub fn snapshotAlloc(self: *const Pane, allocator: std.mem.Allocator) ![]u8 {
        return snapshot_mod.renderAlloc(allocator, &self.engine.state);
    }

    pub fn renderText(self: *const Pane, writer: anytype) !void {
        try text_render.write(writer, &self.engine.state);
    }

    pub fn scrollViewportUp(self: *Pane, lines: usize) void {
        self.engine.state.scrollViewportUp(lines);
    }

    pub fn scrollViewportDown(self: *Pane, lines: usize) void {
        self.engine.state.scrollViewportDown(lines);
    }

    pub fn scrollViewportToBottom(self: *Pane) void {
        self.engine.state.scrollViewportToBottom();
    }

    pub fn screen(self: *const Pane) view_mod.ScreenView {
        return view_mod.ScreenView.init(&self.engine.state);
    }

    fn processIncoming(self: *Pane, bytes: []const u8) !void {
        dumpChunkForDebug(bytes);
        debug_mod.log("pane.processIncoming len={d}", .{bytes.len});
        if (bytes.len != 0) debug_mod.logBytes("pane.chunk", bytes[0..@min(bytes.len, 128)]);
        var responses = std.ArrayList(u8).empty;
        defer responses.deinit(self.allocator);

        for (bytes, 0..) |byte, index| {
            debug_mod.log("pane.byte idx={d} value=0x{x}", .{ index, byte });
            const action = self.engine.nextAction(byte) orelse continue;
            debug_mod.log("pane.action idx={d} tag={s}", .{ index, @tagName(action) });
            try self.handleAction(action, &responses);
            while (self.engine.nextPendingAction()) |pending| {
                debug_mod.log("pane.pending idx={d} tag={s}", .{ index, @tagName(pending) });
                try self.handleAction(pending, &responses);
            }
        }

        if (responses.items.len != 0 and self.pty != null) {
            debug_mod.logBytes("pane.responses", responses.items);
            try self.sendInput(responses.items);
        }
    }

    fn handleAction(self: *Pane, action: action_mod.Action, responses: *std.ArrayList(u8)) !void {
        switch (action) {
            else => {
                self.engine.state.apply(action);
                if (self.engine.state.drainResponse()) |response| {
                    try responses.appendSlice(self.allocator, response);
                }
            },
        }
    }
};

fn dumpChunkForDebug(bytes: []const u8) void {
    if (bytes.len < 1000) return;
    const file = std.fs.createFileAbsolute("C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\claude-crash-chunk.bin", .{ .truncate = true }) catch return;
    defer file.close();
    file.writeAll(bytes) catch {};
}

test "pane runs a command and exposes screen view" {
    var pane = try Pane.init(std.testing.allocator, .{ .rows = 6, .cols = 40 });
    defer pane.deinit();

    var result = try pane.runToEnd(&.{ "zig", "version" }, null);
    defer result.deinit(std.testing.allocator);

    const screen = pane.screen();
    try std.testing.expect(screen.rows() == 6);
    try std.testing.expect(screen.cols() == 40);
}

test "pane drains pending parser actions before consuming the next byte" {
    var pane = try Pane.init(std.testing.allocator, .{ .rows = 6, .cols = 20 });
    defer pane.deinit();

    try pane.processIncoming("\x1b[1;4m\x1b[5;10HX");

    try std.testing.expectEqual(@as(u21, 'X'), pane.engine.state.grid.getConst(4, 9).char);
    try std.testing.expectEqual(@as(u21, ' '), pane.engine.state.grid.getConst(0, 0).char);
}
