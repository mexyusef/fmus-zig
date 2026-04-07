const std = @import("std");
const automation_mod = @import("automation.zig");
const automation_ws_mod = @import("automation_ws.zig");
const runtime_mod = @import("runtime.zig");

pub const Config = struct {
    address: []const u8 = "127.0.0.1",
    port: u16 = 9311,
    protocol: ?[]const u8 = "fmus.automation.v1",
    event_log_path: ?[]const u8 = null,
    host: automation_mod.HostConfig = .{},
};

pub const Service = struct {
    allocator: std.mem.Allocator,
    config: Config,
    host: automation_mod.AutomationHost,
    mutex: std.Thread.Mutex = .{},
    started: bool = false,
    session_id: ?automation_mod.SessionId = null,
    thread: ?std.Thread = null,
    last_error: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, config: Config) Service {
        var host_config = config.host;
        if (host_config.event_log_path == null) {
            host_config.event_log_path = config.event_log_path;
        }
        return .{
            .allocator = allocator,
            .config = config,
            .host = automation_mod.AutomationHost.init(allocator, host_config),
        };
    }

    pub fn deinit(self: *Service) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (!self.started) {
            self.host.deinit();
        }
        if (self.last_error) |msg| self.allocator.free(msg);
    }

    pub fn start(self: *Service, runtime: *runtime_mod.Runtime) !automation_mod.SessionId {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.started) return self.session_id orelse error.InvalidState;
        self.session_id = try self.host.attachRuntime(runtime);
        self.started = true;
        self.thread = try std.Thread.spawn(.{}, threadMain, .{self});
        return self.session_id.?;
    }

    pub fn isStarted(self: *Service) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.started;
    }

    pub fn endpointAlloc(self: *Service, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "ws://{s}:{d}", .{ self.config.address, self.config.port });
    }

    pub fn lastErrorAlloc(self: *Service, allocator: std.mem.Allocator) !?[]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.last_error) |msg| return allocator.dupe(u8, msg);
        return null;
    }

    fn threadMain(self: *Service) void {
        var server = automation_ws_mod.AutomationWsServer.init(self.allocator, &self.host, .{
            .address = self.config.address,
            .port = self.config.port,
            .protocol = self.config.protocol,
        });
        server.listen() catch |err| {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.last_error) |msg| self.allocator.free(msg);
            self.last_error = std.fmt.allocPrint(self.allocator, "{s}", .{@errorName(err)}) catch null;
        };
    }
};
