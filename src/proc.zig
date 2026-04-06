const std = @import("std");

pub const Result = struct {
    allocator: std.mem.Allocator,
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    pub fn deinit(self: *Result) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }

    pub fn ok(self: *const Result) bool {
        return switch (self.term) {
            .Exited => |code| code == 0,
            else => false,
        };
    }

    pub fn text(self: *const Result) []const u8 {
        return self.stdout;
    }
};

pub const Cmd = struct {
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
    max_output_bytes: usize = 1024 * 1024,

    pub fn init(argv: []const []const u8) Cmd {
        return .{ .argv = argv };
    }

    pub fn in(self: Cmd, cwd: []const u8) Cmd {
        var next = self;
        next.cwd = cwd;
        return next;
    }

    pub fn run(self: Cmd, allocator: std.mem.Allocator) !Result {
        const out = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = self.argv,
            .cwd = self.cwd,
            .max_output_bytes = self.max_output_bytes,
        });
        return .{
            .allocator = allocator,
            .stdout = out.stdout,
            .stderr = out.stderr,
            .term = out.term,
        };
    }

    pub fn text(self: Cmd, allocator: std.mem.Allocator) ![]u8 {
        var out = try self.run(allocator);
        errdefer out.deinit();
        const result = out.stdout;
        out.stdout = &.{};
        allocator.free(out.stderr);
        out.stderr = &.{};
        return result;
    }
};

pub fn cmd(argv: []const []const u8) Cmd {
    return Cmd.init(argv);
}

test "cmd builds process wrapper" {
    const c = cmd(&.{ "git", "--version" }).in(".");
    try std.testing.expectEqualStrings("git", c.argv[0]);
    try std.testing.expectEqualStrings(".", c.cwd.?);
}
