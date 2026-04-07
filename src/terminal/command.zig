const builtin = @import("builtin");
const std = @import("std");

pub const ShellCommand = struct {
    allocator: std.mem.Allocator,
    argv: []const []const u8,

    pub fn deinit(self: *ShellCommand) void {
        self.allocator.free(self.argv);
    }
};

pub fn shellCommandAlloc(allocator: std.mem.Allocator, command: []const u8) !ShellCommand {
    return switch (builtin.os.tag) {
        .windows => blk: {
            const argv = try allocator.alloc([]const u8, 4);
            argv[0] = "C:\\Windows\\System32\\cmd.exe";
            argv[1] = "/d";
            argv[2] = "/c";
            argv[3] = command;
            break :blk .{
                .allocator = allocator,
                .argv = argv,
            };
        },
        else => error.UnsupportedPlatform,
    };
}
