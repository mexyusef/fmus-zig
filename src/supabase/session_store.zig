const std = @import("std");
const root = @import("root");
const fs = if (@hasDecl(root, "fs")) root.fs else @import("../fs.zig");
const json = if (@hasDecl(root, "json")) root.json else @import("../json.zig");
const session_mod = @import("session.zig");

pub const Store = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        load: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!?session_mod.Session,
        save: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, session: session_mod.Session) anyerror!void,
        clear: *const fn (ctx: *anyopaque) anyerror!void,
    };

    pub fn load(self: Store, allocator: std.mem.Allocator) !?session_mod.Session {
        return try self.vtable.load(self.ctx, allocator);
    }

    pub fn save(self: Store, allocator: std.mem.Allocator, session: session_mod.Session) !void {
        try self.vtable.save(self.ctx, allocator, session);
    }

    pub fn clear(self: Store) !void {
        try self.vtable.clear(self.ctx);
    }
};

pub const MemoryStore = struct {
    allocator: std.mem.Allocator,
    session: ?session_mod.Session = null,

    pub fn init(allocator: std.mem.Allocator) MemoryStore {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *MemoryStore) void {
        if (self.session) |*session| session_mod.deinit(self.allocator, session);
    }

    pub fn asStore(self: *MemoryStore) Store {
        return .{
            .ctx = self,
            .vtable = &.{
                .load = load,
                .save = save,
                .clear = clear,
            },
        };
    }

    fn load(ctx: *anyopaque, allocator: std.mem.Allocator) !?session_mod.Session {
        const self: *MemoryStore = @ptrCast(@alignCast(ctx));
        if (self.session) |session| return try session_mod.clone(allocator, session);
        return null;
    }

    fn save(ctx: *anyopaque, allocator: std.mem.Allocator, session: session_mod.Session) !void {
        const self: *MemoryStore = @ptrCast(@alignCast(ctx));
        if (self.session) |*stored| session_mod.deinit(self.allocator, stored);
        self.session = try session_mod.clone(allocator, session);
    }

    fn clear(ctx: *anyopaque) !void {
        const self: *MemoryStore = @ptrCast(@alignCast(ctx));
        if (self.session) |*stored| {
            session_mod.deinit(self.allocator, stored);
            self.session = null;
        }
    }
};

pub const FileStore = struct {
    path: []const u8,

    pub fn init(path: []const u8) FileStore {
        return .{ .path = path };
    }

    pub fn asStore(self: *FileStore) Store {
        return .{
            .ctx = self,
            .vtable = &.{
                .load = load,
                .save = save,
                .clear = clear,
            },
        };
    }

    fn load(ctx: *anyopaque, allocator: std.mem.Allocator) !?session_mod.Session {
        const self: *FileStore = @ptrCast(@alignCast(ctx));
        if (!fs.exists(self.path)) return null;
        return try json.parseFile(allocator, session_mod.Session, self.path);
    }

    fn save(ctx: *anyopaque, _: std.mem.Allocator, session: session_mod.Session) !void {
        const self: *FileStore = @ptrCast(@alignCast(ctx));
        try fs.writeJson(self.path, session);
    }

    fn clear(ctx: *anyopaque) !void {
        const self: *FileStore = @ptrCast(@alignCast(ctx));
        fs.remove(self.path) catch {};
    }
};

test "memory store saves loads and clears session" {
    var mem = MemoryStore.init(std.testing.allocator);
    defer mem.deinit();
    const store = mem.asStore();

    try store.save(std.testing.allocator, .{
        .access_token = "a",
        .refresh_token = "r",
        .token_type = "bearer",
    });

    var loaded = (try store.load(std.testing.allocator)).?;
    defer session_mod.deinit(std.testing.allocator, &loaded);
    try std.testing.expectEqualStrings("a", loaded.access_token);

    try store.clear();
    try std.testing.expectEqual(@as(?session_mod.Session, null), try store.load(std.testing.allocator));
}

test "file store roundtrips session json" {
    const path = "__fmus_supabase_session_store.json";
    defer fs.remove(path) catch {};

    var file_store = FileStore.init(path);
    const store = file_store.asStore();

    try store.save(std.testing.allocator, .{
        .access_token = "a",
        .refresh_token = "r",
        .token_type = "bearer",
    });
    var loaded = (try store.load(std.testing.allocator)).?;
    defer session_mod.deinit(std.testing.allocator, &loaded);

    try std.testing.expectEqualStrings("r", loaded.refresh_token.?);
}
