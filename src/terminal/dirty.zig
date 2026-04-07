const std = @import("std");

pub const DirtyRows = struct {
    pub const max_rows = 256;

    bits: [4]u64 = .{ 0, 0, 0, 0 },

    pub fn mark(self: *DirtyRows, row: usize) void {
        if (row >= max_rows) return;
        self.bits[row >> 6] |= @as(u64, 1) << @intCast(row & 63);
    }

    pub fn markRange(self: *DirtyRows, top: usize, bottom: usize) void {
        if (top > bottom) return;
        const lo = @min(top, max_rows - 1);
        const hi = @min(bottom, max_rows - 1);
        for (lo..hi + 1) |row| self.mark(row);
    }

    pub fn markAll(self: *DirtyRows, rows: usize) void {
        self.clear();
        if (rows == 0) return;
        const n = @min(rows, max_rows);
        const full_words = n >> 6;
        for (0..full_words) |i| self.bits[i] = ~@as(u64, 0);
        const rem: u6 = @intCast(n & 63);
        if (rem > 0 and full_words < self.bits.len) {
            self.bits[full_words] = (@as(u64, 1) << rem) -% 1;
        }
    }

    pub fn isDirty(self: *const DirtyRows, row: usize) bool {
        if (row >= max_rows) return false;
        return (self.bits[row >> 6] & (@as(u64, 1) << @intCast(row & 63))) != 0;
    }

    pub fn any(self: *const DirtyRows) bool {
        return (self.bits[0] | self.bits[1] | self.bits[2] | self.bits[3]) != 0;
    }

    pub fn clear(self: *DirtyRows) void {
        self.bits = .{ 0, 0, 0, 0 };
    }
};

test "dirty rows mark and clear" {
    var d = DirtyRows{};
    d.mark(5);
    d.markRange(10, 12);
    try std.testing.expect(d.isDirty(5));
    try std.testing.expect(d.isDirty(10));
    try std.testing.expect(d.isDirty(11));
    try std.testing.expect(d.isDirty(12));
    try std.testing.expect(d.any());
    d.clear();
    try std.testing.expect(!d.any());
}

test "dirty rows mark all" {
    var d = DirtyRows{};
    d.markAll(70);
    try std.testing.expect(d.isDirty(0));
    try std.testing.expect(d.isDirty(63));
    try std.testing.expect(d.isDirty(69));
    try std.testing.expect(!d.isDirty(70));
}
