const std = @import("std");

pub const Cursor = struct {
    input: []const u8,
    pos: usize = 0,

    pub fn init(input: []const u8) Cursor {
        return .{ .input = input };
    }

    pub fn eof(self: *const Cursor) bool {
        return self.pos >= self.input.len;
    }

    pub fn rest(self: *const Cursor) []const u8 {
        return self.input[self.pos..];
    }

    pub fn lit(self: *Cursor, token: []const u8) bool {
        if (!std.mem.startsWith(u8, self.rest(), token)) return false;
        self.pos += token.len;
        return true;
    }

    pub fn ws(self: *Cursor) void {
        while (!self.eof() and std.ascii.isWhitespace(self.input[self.pos])) : (self.pos += 1) {}
    }

    pub fn takeWhile(self: *Cursor, comptime pred: fn (u8) bool) []const u8 {
        const start = self.pos;
        while (!self.eof() and pred(self.input[self.pos])) : (self.pos += 1) {}
        return self.input[start..self.pos];
    }

    pub fn ident(self: *Cursor) ?[]const u8 {
        const start = self.pos;
        if (self.eof()) return null;
        const first = self.input[self.pos];
        if (!(std.ascii.isAlphabetic(first) or first == '_')) return null;
        self.pos += 1;
        while (!self.eof()) {
            const c = self.input[self.pos];
            if (!(std.ascii.isAlphanumeric(c) or c == '_')) break;
            self.pos += 1;
        }
        return self.input[start..self.pos];
    }

    pub fn int(self: *Cursor) !?i64 {
        const start = self.pos;
        if (!self.eof() and (self.input[self.pos] == '-' or self.input[self.pos] == '+')) self.pos += 1;
        const digits = self.takeWhile(struct {
            fn f(c: u8) bool {
                return std.ascii.isDigit(c);
            }
        }.f);
        if (digits.len == 0) {
            self.pos = start;
            return null;
        }
        return try std.fmt.parseInt(i64, self.input[start..self.pos], 10);
    }
};

test "cursor parses identifier and int" {
    var c = Cursor.init("hello 42");
    try std.testing.expectEqualStrings("hello", c.ident().?);
    c.ws();
    try std.testing.expectEqual(@as(?i64, 42), try c.int());
}
