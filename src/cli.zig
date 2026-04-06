const std = @import("std");

pub const Parser = struct {
    argv: []const []const u8,
    index: usize = 0,

    pub fn init(argv: []const []const u8) Parser {
        return .{ .argv = argv };
    }

    pub fn skipExe(self: *Parser) void {
        if (self.index == 0 and self.argv.len > 0) self.index = 1;
    }

    pub fn peek(self: *const Parser) ?[]const u8 {
        if (self.index >= self.argv.len) return null;
        return self.argv[self.index];
    }

    pub fn next(self: *Parser) ?[]const u8 {
        const item = self.peek() orelse return null;
        self.index += 1;
        return item;
    }

    pub fn positional(self: *Parser) ?[]const u8 {
        while (self.peek()) |item| {
            if (!std.mem.startsWith(u8, item, "-")) {
                self.index += 1;
                return item;
            }
            self.index += 1;
        }
        return null;
    }

    pub fn flag(self: *Parser, name: []const u8) bool {
        var i = self.index;
        while (i < self.argv.len) : (i += 1) {
            if (std.mem.eql(u8, self.argv[i], name)) return true;
        }
        return false;
    }

    pub fn value(self: *Parser, name: []const u8) ?[]const u8 {
        var i = self.index;
        while (i < self.argv.len) : (i += 1) {
            const arg = self.argv[i];
            if (std.mem.eql(u8, arg, name)) {
                if (i + 1 < self.argv.len) return self.argv[i + 1];
                return null;
            }
            if (std.mem.startsWith(u8, arg, name) and arg.len > name.len and arg[name.len] == '=') {
                return arg[name.len + 1 ..];
            }
        }
        return null;
    }
};

test "parser reads flag and value" {
    var parser = Parser.init(&.{ "tool", "--port", "8080", "--debug" });
    parser.skipExe();
    try std.testing.expect(parser.flag("--debug"));
    try std.testing.expectEqualStrings("8080", parser.value("--port").?);
}
