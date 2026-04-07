const std = @import("std");
const runtime_mod = @import("runtime.zig");
const platform = @import("../platform.zig");

pub const SessionId = u64;
pub const CursorInfo = runtime_mod.Runtime.CursorInfo;
pub const ProcessInfo = runtime_mod.Runtime.ProcessInfo;
pub const BufferSnapshot = runtime_mod.Runtime.BufferSnapshot;
pub const InputLogEntry = runtime_mod.Runtime.InputLogEntry;
pub const CommandRecord = runtime_mod.Runtime.CommandRecord;
pub const ShellState = runtime_mod.Runtime.ShellState;

pub const Capabilities = packed struct(u16) {
    create_session: bool = true,
    close_session: bool = true,
    input: bool = true,
    control: bool = true,
    resize_terminal: bool = true,
    window: bool = true,
    read_text: bool = true,
    read_metadata: bool = true,
    screenshot: bool = true,
    clipboard: bool = true,
    reserved0: bool = false,
    reserved1: bool = false,
    reserved2: bool = false,
    reserved3: bool = false,
    reserved4: bool = false,
    reserved5: bool = false,

    pub fn all() Capabilities {
        return .{};
    }

    pub fn readOnly() Capabilities {
        return .{
            .create_session = false,
            .close_session = false,
            .input = false,
            .control = false,
            .resize_terminal = false,
            .window = false,
            .screenshot = false,
            .clipboard = false,
        };
    }
};

pub const Policy = struct {
    allow_create_sessions: bool = true,
    allow_attach_sessions: bool = true,
    default_capabilities: Capabilities = Capabilities.all(),
};

pub const EventKind = enum {
    session_created,
    session_closed,
    input_sent,
    control_sent,
    escape_sent,
    screen_changed,
    resized,
    window_changed,
    title_changed,
    cwd_changed,
    process_exited,
    screenshot_saved,
    screenshot_copied,
    fullscreen_toggled,
    zen_toggled,
};

pub const Event = struct {
    generation: u64,
    session_id: SessionId,
    kind: EventKind,
    text: ?[]u8 = null,

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        if (self.text) |text| allocator.free(text);
    }

    fn clone(self: Event, allocator: std.mem.Allocator) !Event {
        return .{
            .generation = self.generation,
            .session_id = self.session_id,
            .kind = self.kind,
            .text = if (self.text) |text| try allocator.dupe(u8, text) else null,
        };
    }
};

pub const ReplayRecord = struct {
    generation: u64,
    session_id: SessionId,
    kind: EventKind,
    text: ?[]const u8 = null,
};

pub const SessionSummary = struct {
    id: SessionId,
    generation: u64,
    title: []u8,
    cwd: []u8,
    exited: bool,
    exit_code: ?u8,
    capabilities: Capabilities,
    attached: bool,
    owned: bool,
    primary: bool,
    visible: bool,

    pub fn deinit(self: *SessionSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.cwd);
    }
};

pub const Command = union(enum) {
    list_sessions,
    close_session,
    get_capabilities,
    get_primary_session,
    send_text: []const u8,
    invoke_command: []const u8,
    send_ctrl: u8,
    send_escape: []const u8,
    resize_terminal: struct { rows: usize, cols: usize },
    set_window_rect: struct { x: ?i32 = null, y: ?i32 = null, width: ?i32 = null, height: ?i32 = null },
    toggle_fullscreen,
    toggle_zen,
    get_visible_text,
    get_scrollback_text,
    get_visible_buffer,
    get_scrollback_buffer,
    get_metrics,
    get_shell_state,
    get_cursor,
    get_title,
    get_cwd,
    get_process,
    get_last_command,
    get_last_exit_code,
    get_input_log,
    get_command_history,
    save_screenshot_png: []const u8,
    copy_screenshot_clipboard,
    poll_events: u64,
    replay_events,
};

pub const Result = union(enum) {
    none,
    session_id: SessionId,
    generation: u64,
    text: []u8,
    buffer: BufferSnapshot,
    shell_state: ShellState,
    metrics: platform.WindowMetrics,
    cursor: CursorInfo,
    process: ProcessInfo,
    last_exit_code: ?u8,
    capabilities: Capabilities,
    input_log: []InputLogEntry,
    command_history: []CommandRecord,
    sessions: []SessionSummary,
    events: []Event,
    replay: []ReplayRecord,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text => |text| allocator.free(text),
            .buffer => |*buffer| buffer.deinit(allocator),
            .shell_state => |*state| state.deinit(allocator),
            .sessions => |sessions| {
                for (sessions) |*item| item.deinit(allocator);
                allocator.free(sessions);
            },
            .events => |events| {
                for (events) |*item| item.deinit(allocator);
                allocator.free(events);
            },
            .input_log => |items| {
                for (items) |*item| item.deinit(allocator);
                allocator.free(items);
            },
            .command_history => |items| {
                for (items) |*item| item.deinit(allocator);
                allocator.free(items);
            },
            .replay => |records| {
                for (records) |*item| {
                    if (item.text) |text| allocator.free(text);
                }
                allocator.free(records);
            },
            else => {},
        }
    }
};

pub const HostConfig = struct {
    max_events_per_session: usize = 256,
    policy: Policy = .{},
    event_log_path: ?[]const u8 = null,
};

pub const CreateSessionOptions = struct {
    runtime: runtime_mod.Config = .{},
    spawn_shell: bool = true,
    capabilities: ?Capabilities = null,
};

pub const AutomationHost = struct {
    allocator: std.mem.Allocator,
    config: HostConfig,
    mutex: std.Thread.Mutex = .{},
    next_session_id: SessionId = 1,
    primary_session_id: ?SessionId = null,
    sessions: std.ArrayListUnmanaged(Session) = .{},

    const Session = struct {
        id: SessionId,
        runtime: *runtime_mod.Runtime,
        owned: bool,
        capabilities: Capabilities,
        visible: bool,
        generation: u64 = 0,
        last_title: []u8 = &.{},
        last_cwd: []u8 = &.{},
        last_process: ProcessInfo = .{ .exited = false, .exit_code = null },
        events: std.ArrayListUnmanaged(Event) = .{},

        fn deinit(self: *Session, allocator: std.mem.Allocator) void {
            allocator.free(self.last_title);
            allocator.free(self.last_cwd);
            for (self.events.items) |*event| event.deinit(allocator);
            self.events.deinit(allocator);
            if (self.owned) {
                self.runtime.deinit();
                allocator.destroy(self.runtime);
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: HostConfig) AutomationHost {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *AutomationHost) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.sessions.items) |*session| session.deinit(self.allocator);
        self.sessions.deinit(self.allocator);
    }

    pub fn attachRuntime(self: *AutomationHost, runtime: *runtime_mod.Runtime) !SessionId {
        if (!self.config.policy.allow_attach_sessions) return error.AttachDenied;
        self.mutex.lock();
        defer self.mutex.unlock();
        const id = self.nextSessionIdLocked();
        var session = Session{
            .id = id,
            .runtime = runtime,
            .owned = false,
            .capabilities = self.config.policy.default_capabilities,
            .visible = true,
        };
        try self.syncMetadataLocked(&session);
        try self.emitEventLocked(&session, .session_created, "attached");
        try self.sessions.append(self.allocator, session);
        if (self.primary_session_id == null) self.primary_session_id = id;
        return id;
    }

    pub fn createShellSession(self: *AutomationHost, options: CreateSessionOptions) !SessionId {
        if (!self.config.policy.allow_create_sessions) return error.CreateDenied;
        var runtime = try self.allocator.create(runtime_mod.Runtime);
        errdefer self.allocator.destroy(runtime);
        runtime.* = try runtime_mod.Runtime.init(self.allocator, options.runtime);
        errdefer runtime.deinit();
        if (options.spawn_shell) try runtime.spawnDefaultShell();

        self.mutex.lock();
        defer self.mutex.unlock();
        const id = self.nextSessionIdLocked();
        var session = Session{
            .id = id,
            .runtime = runtime,
            .owned = true,
            .capabilities = options.capabilities orelse self.config.policy.default_capabilities,
            .visible = false,
        };
        try self.syncMetadataLocked(&session);
        try self.emitEventLocked(&session, .session_created, "created");
        try self.sessions.append(self.allocator, session);
        if (self.primary_session_id == null) self.primary_session_id = id;
        return id;
    }

    pub fn closeSession(self: *AutomationHost, session_id: SessionId) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const index = self.indexOfSessionLocked(session_id) orelse return error.UnknownSession;
        var session = self.sessions.orderedRemove(index);
        try self.emitEventLocked(&session, .session_closed, "closed");
        if (self.primary_session_id != null and self.primary_session_id.? == session_id) {
            self.primary_session_id = if (self.sessions.items.len != 0) self.sessions.items[0].id else null;
        }
        session.deinit(self.allocator);
    }

    pub fn execute(self: *AutomationHost, session_id: ?SessionId, command: Command) !Result {
        switch (command) {
            .list_sessions => return .{ .sessions = try self.listSessionsAlloc() },
            .replay_events => return .{ .replay = try self.replayEventsAlloc() },
            .get_primary_session => return .{ .session_id = self.primary_session_id orelse return error.NoPrimarySession },
            .close_session => {
                if (!self.config.policy.default_capabilities.close_session) return error.CapabilityDenied;
                try self.closeSession(session_id orelse return error.MissingSessionId);
                return .{ .none = {} };
            },
            else => {},
        }

        self.mutex.lock();
        defer self.mutex.unlock();
        const session = self.getSessionLocked(session_id orelse return error.MissingSessionId) orelse return error.UnknownSession;

        switch (command) {
            .get_capabilities => return .{ .capabilities = session.capabilities },
            .send_text => |text| {
                if (!session.capabilities.input) return error.CapabilityDenied;
                try session.runtime.sendText(text);
                try self.emitEventLocked(session, .input_sent, text);
                try self.afterMutationLocked(session, .screen_changed, null);
                return .{ .generation = session.generation };
            },
            .invoke_command => |text| {
                if (!session.capabilities.input) return error.CapabilityDenied;
                try session.runtime.invokeCommand(text);
                try self.emitEventLocked(session, .input_sent, text);
                try self.afterMutationLocked(session, .screen_changed, null);
                return .{ .generation = session.generation };
            },
            .send_ctrl => |ctrl| {
                if (!session.capabilities.control) return error.CapabilityDenied;
                try session.runtime.sendCtrl(ctrl);
                var buf: [1]u8 = .{ctrl};
                try self.emitEventLocked(session, .control_sent, &buf);
                try self.afterMutationLocked(session, .screen_changed, null);
                return .{ .generation = session.generation };
            },
            .send_escape => |bytes| {
                if (!session.capabilities.control) return error.CapabilityDenied;
                try session.runtime.sendEscape(bytes);
                try self.emitEventLocked(session, .escape_sent, bytes);
                try self.afterMutationLocked(session, .screen_changed, null);
                return .{ .generation = session.generation };
            },
            .resize_terminal => |size| {
                if (!session.capabilities.resize_terminal) return error.CapabilityDenied;
                try session.runtime.resizeTerminal(size.rows, size.cols);
                try self.afterMutationLocked(session, .resized, null);
                return .{ .generation = session.generation };
            },
            .set_window_rect => |rect| {
                if (!session.capabilities.window) return error.CapabilityDenied;
                try session.runtime.setWindowRect(rect.x, rect.y, rect.width, rect.height);
                try self.afterMutationLocked(session, .window_changed, null);
                return .{ .generation = session.generation };
            },
            .toggle_fullscreen => {
                if (!session.capabilities.window) return error.CapabilityDenied;
                try session.runtime.toggleFullscreen();
                try self.afterMutationLocked(session, .fullscreen_toggled, null);
                return .{ .generation = session.generation };
            },
            .toggle_zen => {
                if (!session.capabilities.window) return error.CapabilityDenied;
                try session.runtime.toggleZen();
                try self.afterMutationLocked(session, .zen_toggled, null);
                return .{ .generation = session.generation };
            },
            .get_visible_text => {
                if (!session.capabilities.read_text) return error.CapabilityDenied;
                return .{ .text = try session.runtime.visibleTextAlloc(self.allocator) };
            },
            .get_scrollback_text => {
                if (!session.capabilities.read_text) return error.CapabilityDenied;
                return .{ .text = try session.runtime.scrollbackTextAlloc(self.allocator) };
            },
            .get_visible_buffer => {
                if (!session.capabilities.read_text) return error.CapabilityDenied;
                return .{ .buffer = try session.runtime.visibleBufferAlloc(self.allocator) };
            },
            .get_scrollback_buffer => {
                if (!session.capabilities.read_text) return error.CapabilityDenied;
                return .{ .buffer = try session.runtime.scrollbackBufferAlloc(self.allocator) };
            },
            .get_metrics => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .metrics = session.runtime.metrics() };
            },
            .get_shell_state => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .shell_state = try session.runtime.shellStateAlloc(self.allocator) };
            },
            .get_cursor => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .cursor = session.runtime.cursorInfo() };
            },
            .get_title => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .text = try session.runtime.titleAlloc(self.allocator) };
            },
            .get_cwd => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .text = try session.runtime.cwdAlloc(self.allocator) };
            },
            .get_process => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .process = session.runtime.processInfo() };
            },
            .get_last_command => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .text = try session.runtime.lastCommandAlloc(self.allocator) };
            },
            .get_last_exit_code => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .last_exit_code = session.runtime.lastExitCode() };
            },
            .get_input_log => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .input_log = try session.runtime.inputLogAlloc(self.allocator) };
            },
            .get_command_history => {
                if (!session.capabilities.read_metadata) return error.CapabilityDenied;
                return .{ .command_history = try session.runtime.commandHistoryAlloc(self.allocator) };
            },
            .save_screenshot_png => |path| {
                if (!session.capabilities.screenshot) return error.CapabilityDenied;
                try session.runtime.saveScreenshotPng(path);
                try self.afterMutationLocked(session, .screenshot_saved, path);
                return .{ .generation = session.generation };
            },
            .copy_screenshot_clipboard => {
                if (!session.capabilities.clipboard) return error.CapabilityDenied;
                try session.runtime.copyScreenshotToClipboard();
                try self.afterMutationLocked(session, .screenshot_copied, null);
                return .{ .generation = session.generation };
            },
            .poll_events => |since| return .{ .events = try self.eventsSinceLocked(session, since) },
            .list_sessions, .close_session, .get_primary_session, .replay_events => unreachable,
        }
    }

    pub fn listSessionsAlloc(self: *AutomationHost) ![]SessionSummary {
        self.mutex.lock();
        defer self.mutex.unlock();
        var out = try self.allocator.alloc(SessionSummary, self.sessions.items.len);
        errdefer self.allocator.free(out);
        for (self.sessions.items, 0..) |*session, index| {
            try self.syncMetadataLocked(session);
            out[index] = .{
                .id = session.id,
                .generation = session.generation,
                .title = try session.runtime.titleAlloc(self.allocator),
                .cwd = try session.runtime.cwdAlloc(self.allocator),
                .exited = session.last_process.exited,
                .exit_code = session.last_process.exit_code,
                .capabilities = session.capabilities,
                .attached = !session.owned,
                .owned = session.owned,
                .primary = self.primary_session_id != null and self.primary_session_id.? == session.id,
                .visible = session.visible,
            };
        }
        return out;
    }

    fn nextSessionIdLocked(self: *AutomationHost) SessionId {
        defer self.next_session_id += 1;
        return self.next_session_id;
    }

    fn indexOfSessionLocked(self: *AutomationHost, session_id: SessionId) ?usize {
        for (self.sessions.items, 0..) |session, index| {
            if (session.id == session_id) return index;
        }
        return null;
    }

    fn getSessionLocked(self: *AutomationHost, session_id: SessionId) ?*Session {
        const index = self.indexOfSessionLocked(session_id) orelse return null;
        return &self.sessions.items[index];
    }

    fn emitEventLocked(self: *AutomationHost, session: *Session, kind: EventKind, text: ?[]const u8) !void {
        session.generation += 1;
        if (session.events.items.len >= self.config.max_events_per_session) {
            var old = session.events.orderedRemove(0);
            old.deinit(self.allocator);
        }
        try session.events.append(self.allocator, .{
            .generation = session.generation,
            .session_id = session.id,
            .kind = kind,
            .text = if (text) |value| try self.allocator.dupe(u8, value) else null,
        });
        try self.appendEventLogLocked(.{
            .generation = session.generation,
            .session_id = session.id,
            .kind = kind,
            .text = text,
        });
    }

    fn afterMutationLocked(self: *AutomationHost, session: *Session, kind: EventKind, text: ?[]const u8) !void {
        try self.emitEventLocked(session, kind, text);
        try self.syncMetadataLocked(session);
    }

    fn syncMetadataLocked(self: *AutomationHost, session: *Session) !void {
        const title = try session.runtime.titleAlloc(self.allocator);
        defer self.allocator.free(title);
        if (!std.mem.eql(u8, title, session.last_title)) {
            self.allocator.free(session.last_title);
            session.last_title = try self.allocator.dupe(u8, title);
            try self.emitEventLocked(session, .title_changed, session.last_title);
        }

        const cwd = try session.runtime.cwdAlloc(self.allocator);
        defer self.allocator.free(cwd);
        if (!std.mem.eql(u8, cwd, session.last_cwd)) {
            self.allocator.free(session.last_cwd);
            session.last_cwd = try self.allocator.dupe(u8, cwd);
            try self.emitEventLocked(session, .cwd_changed, session.last_cwd);
        }

        const proc = session.runtime.processInfo();
        if (proc.exited != session.last_process.exited or proc.exit_code != session.last_process.exit_code) {
            session.last_process = proc;
            if (proc.exited) try self.emitEventLocked(session, .process_exited, null);
        }
    }

    fn eventsSinceLocked(self: *AutomationHost, session: *Session, since: u64) ![]Event {
        var count: usize = 0;
        for (session.events.items) |event| {
            if (event.generation > since) count += 1;
        }
        var out = try self.allocator.alloc(Event, count);
        errdefer self.allocator.free(out);
        var index: usize = 0;
        for (session.events.items) |event| {
            if (event.generation <= since) continue;
            out[index] = try event.clone(self.allocator);
            index += 1;
        }
        return out;
    }

    pub fn replayEventsAlloc(self: *AutomationHost) ![]ReplayRecord {
        const path = self.config.event_log_path orelse return self.allocator.alloc(ReplayRecord, 0);
        const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return self.allocator.alloc(ReplayRecord, 0),
            else => return err,
        };
        defer file.close();
        const text = try file.readToEndAlloc(self.allocator, 4 * 1024 * 1024);
        defer self.allocator.free(text);

        var records = std.ArrayList(ReplayRecord).empty;
        defer records.deinit(self.allocator);

        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) continue;
            var parsed = try std.json.parseFromSlice(ReplayRecord, self.allocator, trimmed, .{
                .ignore_unknown_fields = true,
            });
            defer parsed.deinit();
            try records.append(self.allocator, .{
                .generation = parsed.value.generation,
                .session_id = parsed.value.session_id,
                .kind = parsed.value.kind,
                .text = if (parsed.value.text) |value| try self.allocator.dupe(u8, value) else null,
            });
        }
        return records.toOwnedSlice(self.allocator);
    }

    fn appendEventLogLocked(self: *AutomationHost, record: ReplayRecord) !void {
        const path = self.config.event_log_path orelse return;
        const file = try std.fs.createFileAbsolute(path, .{ .truncate = false, .read = true });
        defer file.close();
        try file.seekFromEnd(0);
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        try std.json.Stringify.value(record, .{}, &out.writer);
        try file.writeAll(out.written());
        try file.writeAll("\n");
    }
};

test "automation host attach and query session text" {
    var host = AutomationHost.init(std.testing.allocator, .{});
    defer host.deinit();

    var runtime = try runtime_mod.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    const id = try host.attachRuntime(&runtime);

    var result = try host.execute(id, .get_title);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result == .text);
    try std.testing.expect(std.mem.indexOf(u8, result.text, "FMUS Terminal") != null);
}

test "automation host enforces read only capabilities" {
    var host = AutomationHost.init(std.testing.allocator, .{
        .policy = .{ .default_capabilities = Capabilities.readOnly() },
    });
    defer host.deinit();

    var runtime = try runtime_mod.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    const id = try host.attachRuntime(&runtime);

    try std.testing.expectError(error.CapabilityDenied, host.execute(id, .{ .send_text = "blocked" }));
    var result = try host.execute(id, .get_title);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result == .text);
}

test "automation host replays persisted events" {
    const path = "C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\automation-replay-test.jsonl";
    std.fs.deleteFileAbsolute(path) catch {};

    var host = AutomationHost.init(std.testing.allocator, .{
        .event_log_path = path,
    });
    defer {
        host.deinit();
        std.fs.deleteFileAbsolute(path) catch {};
    }

    var runtime = try runtime_mod.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    _ = try host.attachRuntime(&runtime);

    var result = try host.execute(null, .replay_events);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result == .replay);
    try std.testing.expect(result.replay.len != 0);
}
