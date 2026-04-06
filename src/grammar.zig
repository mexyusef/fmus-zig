const std = @import("std");
const text = @import("text.zig");

pub const Rule = struct {
    name: []const u8,
    expr: []const u8,
};

pub const Grammar = struct {
    allocator: std.mem.Allocator,
    rules: []Rule,

    pub fn deinit(self: *Grammar) void {
        for (self.rules) |rule| {
            self.allocator.free(rule.name);
            self.allocator.free(rule.expr);
        }
        self.allocator.free(self.rules);
    }

    pub fn get(self: *const Grammar, name: []const u8) ?[]const u8 {
        for (self.rules) |rule| {
            if (std.mem.eql(u8, rule.name, name)) return rule.expr;
        }
        return null;
    }
};

pub fn load(allocator: std.mem.Allocator, source: []const u8) !Grammar {
    var rules = std.ArrayList(Rule).empty;
    defer rules.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, source, '\n');
    while (line_it.next()) |raw_line| {
        const line = text.trim(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidGrammarLine;
        const name = text.trim(line[0..colon]);
        const expr = text.trim(line[colon + 1 ..]);
        try rules.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .expr = try allocator.dupe(u8, expr),
        });
    }

    return .{
        .allocator = allocator,
        .rules = try rules.toOwnedSlice(allocator),
    };
}

test "grammar loads named rules" {
    const alloc = std.testing.allocator;
    var g = try load(alloc,
        \\expr: term ("+" term)*
        \\term: NUMBER
    );
    defer g.deinit();
    try std.testing.expectEqualStrings("NUMBER", g.get("term").?);
}
