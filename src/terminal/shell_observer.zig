const std = @import("std");
const buffer_mod = @import("buffer.zig");
const pty_mod = @import("pty.zig");
const state_mod = @import("state.zig");

pub const ShellState = struct {
    shell: pty_mod.ShellType,
    prompt: []u8,
    cwd: []u8,
    last_exit_code: ?u8,

    pub fn deinit(self: *ShellState, allocator: std.mem.Allocator) void {
        allocator.free(self.prompt);
        allocator.free(self.cwd);
    }
};

pub const Observer = struct {
    allocator: std.mem.Allocator,
    shell: pty_mod.ShellType = .auto,
    prompt: []u8,
    cwd: []u8,
    last_exit_code: ?u8 = null,

    pub fn init(allocator: std.mem.Allocator) !Observer {
        return .{
            .allocator = allocator,
            .prompt = try allocator.dupe(u8, ""),
            .cwd = try allocator.dupe(u8, ""),
        };
    }

    pub fn deinit(self: *Observer) void {
        self.allocator.free(self.prompt);
        self.allocator.free(self.cwd);
    }

    pub fn setShell(self: *Observer, shell: pty_mod.ShellType) void {
        self.shell = shell;
    }

    pub fn observe(self: *Observer, state: *const state_mod.State) !void {
        var snap = try buffer_mod.visibleAlloc(self.allocator, state);
        defer snap.deinit(self.allocator);

        for (snap.rows, 0..) |row, idx| {
            if (parseExitCode(row.text)) |code| self.last_exit_code = code;
            _ = idx;
        }

        var row_index = snap.rows.len;
        while (row_index > 0) {
            row_index -= 1;
            const row = snap.rows[row_index].text;
            if (row.len == 0) continue;
            if (parsePrompt(row)) |prompt| {
                try self.replace(&self.prompt, row);
                try self.replace(&self.cwd, prompt.cwd);
                if (self.shell == .auto and prompt.shell != .auto) self.shell = prompt.shell;
                break;
            }
        }
    }

    pub fn stateAlloc(self: *const Observer, allocator: std.mem.Allocator) !ShellState {
        return .{
            .shell = self.shell,
            .prompt = try allocator.dupe(u8, self.prompt),
            .cwd = try allocator.dupe(u8, self.cwd),
            .last_exit_code = self.last_exit_code,
        };
    }

    pub fn buildInvokeInputAlloc(self: *const Observer, allocator: std.mem.Allocator, command: []const u8) ![]u8 {
        return switch (self.shell) {
            .cmd => std.fmt.allocPrint(allocator, "{s} & echo __FMUS_EXIT__={s}%errorlevel%{s}\r", .{ command, "", "" }),
            .pwsh, .powershell => std.fmt.allocPrint(allocator, "{s}; Write-Host \"__FMUS_EXIT__=$LASTEXITCODE\"\r", .{command}),
            .auto => std.fmt.allocPrint(allocator, "{s}\r", .{command}),
        };
    }

    fn replace(self: *Observer, target: *[]u8, value: []const u8) !void {
        if (std.mem.eql(u8, target.*, value)) return;
        self.allocator.free(target.*);
        target.* = try self.allocator.dupe(u8, value);
    }
};

const PromptInfo = struct {
    shell: pty_mod.ShellType,
    cwd: []const u8,
};

fn parsePrompt(line: []const u8) ?PromptInfo {
    if (line.len >= 4 and std.mem.startsWith(u8, line, "PS ") and line[line.len - 1] == '>') {
        return .{
            .shell = .pwsh,
            .cwd = std.mem.trim(u8, line[3 .. line.len - 1], " "),
        };
    }
    if (line.len >= 3 and line[line.len - 1] == '>') {
        if (std.ascii.isAlphabetic(line[0]) and line[1] == ':') {
            return .{
                .shell = .cmd,
                .cwd = line[0 .. line.len - 1],
            };
        }
        if (std.mem.startsWith(u8, line, "\\\\")) {
            return .{
                .shell = .cmd,
                .cwd = line[0 .. line.len - 1],
            };
        }
    }
    return null;
}

fn parseExitCode(line: []const u8) ?u8 {
    const prefix = "__FMUS_EXIT__=";
    const index = std.mem.indexOf(u8, line, prefix) orelse return null;
    const rest = line[index + prefix.len ..];
    var end: usize = 0;
    while (end < rest.len and std.ascii.isDigit(rest[end])) : (end += 1) {}
    if (end == 0) return null;
    return std.fmt.parseInt(u8, rest[0..end], 10) catch null;
}

test "shell observer parses cmd prompt and exit marker" {
    var state = try state_mod.State.init(std.testing.allocator, 4, 40);
    defer state.deinit();
    state.apply(.{ .print = 'C' });
    state.apply(.{ .print = ':' });
    state.apply(.{ .print = '\\' });
    state.apply(.{ .print = 'w' });
    state.apply(.{ .print = 'o' });
    state.apply(.{ .print = 'r' });
    state.apply(.{ .print = 'k' });
    state.apply(.{ .print = '>' });
    state.apply(.carriage_return);
    state.apply(.line_feed);
    for ("__FMUS_EXIT__=7") |ch| state.apply(.{ .print = ch });

    var observer = try Observer.init(std.testing.allocator);
    defer observer.deinit();
    try observer.observe(&state);
    try std.testing.expectEqual(pty_mod.ShellType.cmd, observer.shell);
    try std.testing.expectEqualStrings("C:\\work>", observer.prompt);
    try std.testing.expectEqualStrings("C:\\work", observer.cwd);
    try std.testing.expectEqual(@as(?u8, 7), observer.last_exit_code);
}
