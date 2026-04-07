const builtin = @import("builtin");
const std = @import("std");
const env = @import("../env.zig");

pub const Kind = enum {
    cmd,
    powershell,
    pwsh,
};

pub const Launch = struct {
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    prompt_kick_input: []const u8 = "\r",
    bootstrap_input: []const u8 = "",

    pub fn deinit(self: *Launch) void {
        self.allocator.free(self.argv);
    }
};

pub fn detectDefault(allocator: std.mem.Allocator) !Kind {
    _ = allocator;
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    if (try env.get(std.heap.page_allocator, "FMUS_TERMINAL_SHELL")) |value| {
        defer std.heap.page_allocator.free(value);
        if (std.ascii.eqlIgnoreCase(value, "pwsh")) return .pwsh;
        if (std.ascii.eqlIgnoreCase(value, "powershell")) return .powershell;
        if (std.ascii.eqlIgnoreCase(value, "cmd")) return .cmd;
    }

    return .cmd;
}

pub fn launchDefault(allocator: std.mem.Allocator) !Launch {
    return launch(allocator, try detectDefault(allocator));
}

pub fn launch(allocator: std.mem.Allocator, kind: Kind) !Launch {
    return switch (kind) {
        .cmd => launchCmd(allocator),
        .powershell => launchPowerShell(allocator, false),
        .pwsh => launchPowerShell(allocator, true),
    };
}

fn launchCmd(allocator: std.mem.Allocator) !Launch {
    const argv = try allocator.alloc([]const u8, 5);
    argv[0] = "C:\\Windows\\System32\\cmd.exe";
    argv[1] = "/D";
    argv[2] = "/Q";
    argv[3] = "/K";
    argv[4] = "prompt $P$G";
    return .{
        .allocator = allocator,
        .argv = argv,
        .prompt_kick_input = "\r",
        .bootstrap_input = "",
    };
}

fn launchPowerShell(allocator: std.mem.Allocator, modern: bool) !Launch {
    const argv = try allocator.alloc([]const u8, 4);
    argv[0] = if (modern) "pwsh.exe" else "powershell.exe";
    argv[1] = "-NoLogo";
    argv[2] = "-NoExit";
    argv[3] = "-Command";
    const command = if (modern)
        "$Host.UI.RawUI.WindowTitle='FMUS'; function prompt { \"PS $($executionContext.SessionState.Path.CurrentLocation)> \" }; ''"
    else
        "$Host.UI.RawUI.WindowTitle='FMUS'; function prompt { \"PS $($executionContext.SessionState.Path.CurrentLocation)> \" }; ''";

    const full = try allocator.alloc([]const u8, 5);
    allocator.free(argv);
    full[0] = if (modern) "pwsh.exe" else "powershell.exe";
    full[1] = "-NoLogo";
    full[2] = "-NoExit";
    full[3] = "-Command";
    full[4] = command;
    return .{
        .allocator = allocator,
        .argv = full,
        .prompt_kick_input = "\r",
        .bootstrap_input = "Get-Location\r",
    };
}

fn commandExists(name: []const u8) bool {
    var child = std.process.Child.init(&.{ "where.exe", name }, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return false;
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

test "default shell launch builds argv" {
    if (builtin.os.tag != .windows) return;
    var launch_spec = try launch(std.testing.allocator, .cmd);
    defer launch_spec.deinit();
    try std.testing.expect(launch_spec.argv.len >= 5);
}
