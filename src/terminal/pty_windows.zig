const std = @import("std");
const windows = std.os.windows;

const HANDLE = windows.HANDLE;
const DWORD = windows.DWORD;
const BOOL = windows.BOOL;
const LPVOID = windows.LPVOID;
const LPCWSTR = [*:0]const u16;
const WORD = u16;
const BYTE = u8;
const INVALID_HANDLE = windows.INVALID_HANDLE_VALUE;

const HPCON = *opaque {};
const EXTENDED_STARTUPINFO_PRESENT: DWORD = 0x00080000;
const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;
const PSEUDOCONSOLE_PASSTHROUGH: DWORD = 0x00000008;
const S_OK: c_long = 0;
const WAIT_OBJECT_0: DWORD = 0;
const STILL_ACTIVE: DWORD = 259;
const HANDLE_FLAG_INHERIT: DWORD = 0x00000001;

const COORD = extern struct {
    x: c_short,
    y: c_short,
};

const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD,
    lpSecurityDescriptor: ?LPVOID,
    bInheritHandle: BOOL,
};

const STARTUPINFOW = extern struct {
    cb: DWORD,
    lpReserved: ?LPCWSTR,
    lpDesktop: ?LPCWSTR,
    lpTitle: ?LPCWSTR,
    dwX: DWORD,
    dwY: DWORD,
    dwXSize: DWORD,
    dwYSize: DWORD,
    dwXCountChars: DWORD,
    dwYCountChars: DWORD,
    dwFillAttribute: DWORD,
    dwFlags: DWORD,
    wShowWindow: WORD,
    cbReserved2: WORD,
    lpReserved2: ?*BYTE,
    hStdInput: ?HANDLE,
    hStdOutput: ?HANDLE,
    hStdError: ?HANDLE,
};

const LPPROC_THREAD_ATTRIBUTE_LIST = *opaque {};

const STARTUPINFOEXW = extern struct {
    StartupInfo: STARTUPINFOW,
    lpAttributeList: ?LPPROC_THREAD_ATTRIBUTE_LIST,
};

const PROCESS_INFORMATION = extern struct {
    hProcess: HANDLE,
    hThread: HANDLE,
    dwProcessId: DWORD,
    dwThreadId: DWORD,
};

const OVERLAPPED = extern struct {
    Internal: usize = 0,
    InternalHigh: usize = 0,
    Offset: DWORD = 0,
    OffsetHigh: DWORD = 0,
    hEvent: ?HANDLE = null,
};

const PIPE_ACCESS_INBOUND: DWORD = 0x00000001;
const PIPE_TYPE_BYTE_WAIT: DWORD = 0x00000000;
const FILE_FLAG_OVERLAPPED: DWORD = 0x40000000;
const WIN_GENERIC_WRITE: DWORD = 0x40000000;
const OPEN_EXISTING: DWORD = 3;
const INFINITE: DWORD = 0xFFFFFFFF;
const INVALID_FILE_ATTRIBUTES: DWORD = 0xFFFFFFFF;

extern "kernel32" fn CreatePipe(
    hReadPipe: *HANDLE,
    hWritePipe: *HANDLE,
    lpPipeAttributes: ?*const SECURITY_ATTRIBUTES,
    nSize: DWORD,
) callconv(.winapi) BOOL;

extern "kernel32" fn CreatePseudoConsole(
    size: COORD,
    hInput: HANDLE,
    hOutput: HANDLE,
    dwFlags: DWORD,
    phPC: *HPCON,
) callconv(.winapi) c_long;

extern "kernel32" fn ResizePseudoConsole(
    hPC: HPCON,
    size: COORD,
) callconv(.winapi) c_long;

extern "kernel32" fn ClosePseudoConsole(hPC: HPCON) callconv(.winapi) void;

extern "kernel32" fn InitializeProcThreadAttributeList(
    lpAttributeList: ?LPPROC_THREAD_ATTRIBUTE_LIST,
    dwAttributeCount: DWORD,
    dwFlags: DWORD,
    lpSize: *usize,
) callconv(.winapi) BOOL;

extern "kernel32" fn UpdateProcThreadAttribute(
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
    dwFlags: DWORD,
    Attribute: usize,
    lpValue: ?*const anyopaque,
    cbSize: usize,
    lpPreviousValue: ?LPVOID,
    lpReturnSize: ?*usize,
) callconv(.winapi) BOOL;

extern "kernel32" fn DeleteProcThreadAttributeList(
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
) callconv(.winapi) void;

extern "kernel32" fn CreateProcessW(
    lpApplicationName: ?LPCWSTR,
    lpCommandLine: ?[*:0]u16,
    lpProcessAttributes: ?*SECURITY_ATTRIBUTES,
    lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
    bInheritHandles: BOOL,
    dwCreationFlags: DWORD,
    lpEnvironment: ?LPVOID,
    lpCurrentDirectory: ?LPCWSTR,
    lpStartupInfo: *STARTUPINFOEXW,
    lpProcessInformation: *PROCESS_INFORMATION,
) callconv(.winapi) BOOL;

extern "kernel32" fn PeekNamedPipe(
    hNamedPipe: HANDLE,
    lpBuffer: ?[*]u8,
    nBufferSize: DWORD,
    lpBytesRead: ?*DWORD,
    lpTotalBytesAvail: ?*DWORD,
    lpBytesLeftThisMessage: ?*DWORD,
) callconv(.winapi) BOOL;

extern "kernel32" fn ReadFile(
    hFile: HANDLE,
    lpBuffer: [*]u8,
    nNumberOfBytesToRead: DWORD,
    lpNumberOfBytesRead: ?*DWORD,
    lpOverlapped: ?LPVOID,
) callconv(.winapi) BOOL;

extern "kernel32" fn WriteFile(
    hFile: HANDLE,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: DWORD,
    lpNumberOfBytesWritten: ?*DWORD,
    lpOverlapped: ?LPVOID,
) callconv(.winapi) BOOL;

extern "kernel32" fn WaitForSingleObject(
    hHandle: HANDLE,
    dwMilliseconds: DWORD,
) callconv(.winapi) DWORD;

extern "kernel32" fn GetExitCodeProcess(
    hProcess: HANDLE,
    lpExitCode: *DWORD,
) callconv(.winapi) BOOL;

extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn SetHandleInformation(hObject: HANDLE, dwMask: DWORD, dwFlags: DWORD) callconv(.winapi) BOOL;

extern "kernel32" fn CreateNamedPipeW(
    lpName: LPCWSTR,
    dwOpenMode: DWORD,
    dwPipeMode: DWORD,
    nMaxInstances: DWORD,
    nOutBufferSize: DWORD,
    nInBufferSize: DWORD,
    nDefaultTimeOut: DWORD,
    lpSecurityAttributes: ?*const SECURITY_ATTRIBUTES,
) callconv(.winapi) HANDLE;

extern "kernel32" fn CreateFileW(
    lpFileName: LPCWSTR,
    dwDesiredAccess: DWORD,
    dwShareMode: DWORD,
    lpSecurityAttributes: ?*const SECURITY_ATTRIBUTES,
    dwCreationDisposition: DWORD,
    dwFlagsAndAttributes: DWORD,
    hTemplateFile: ?HANDLE,
) callconv(.winapi) HANDLE;

extern "kernel32" fn CreateEventW(
    lpEventAttributes: ?*const SECURITY_ATTRIBUTES,
    bManualReset: BOOL,
    bInitialState: BOOL,
    lpName: ?LPCWSTR,
) callconv(.winapi) HANDLE;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) DWORD;
extern "kernel32" fn CreateThread(
    lpThreadAttributes: ?*const SECURITY_ATTRIBUTES,
    dwStackSize: usize,
    lpStartAddress: *const fn (?*anyopaque) callconv(.winapi) DWORD,
    lpParameter: ?*anyopaque,
    dwCreationFlags: DWORD,
    lpThreadId: ?*DWORD,
) callconv(.winapi) ?HANDLE;
extern "kernel32" fn SetEvent(hEvent: HANDLE) callconv(.winapi) BOOL;

extern "kernel32" fn GetOverlappedResult(
    hFile: HANDLE,
    lpOverlapped: *OVERLAPPED,
    lpNumberOfBytesTransferred: *DWORD,
    bWait: BOOL,
) callconv(.winapi) BOOL;

extern "kernel32" fn ResetEvent(hEvent: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn SetConsoleOutputCP(wCodePageID: c_uint) callconv(.winapi) BOOL;
extern "kernel32" fn SetConsoleCP(wCodePageID: c_uint) callconv(.winapi) BOOL;
extern "kernel32" fn AllocConsole() callconv(.winapi) BOOL;
extern "kernel32" fn GetConsoleWindow() callconv(.winapi) ?windows.HWND;
extern "kernel32" fn SetEnvironmentVariableW(
    lpName: LPCWSTR,
    lpValue: ?LPCWSTR,
) callconv(.winapi) BOOL;

pub const SpawnConfig = struct {
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
    rows: u16 = 24,
    cols: u16 = 80,
    shell: ShellType = .auto,
};

pub const ShellType = enum {
    auto,
    cmd,
    pwsh,
    powershell,

    pub fn detect(argv: []const []const u8) ShellType {
        if (argv.len == 0) return .auto;
        const exe = argv[0];
        const base = if (std.mem.lastIndexOfScalar(u8, exe, '\\')) |pos| exe[pos + 1 ..] else exe;
        if (std.ascii.eqlIgnoreCase(base, "cmd") or std.ascii.eqlIgnoreCase(base, "cmd.exe")) return .cmd;
        if (std.ascii.eqlIgnoreCase(base, "pwsh") or std.ascii.eqlIgnoreCase(base, "pwsh.exe")) return .pwsh;
        if (std.ascii.eqlIgnoreCase(base, "powershell") or std.ascii.eqlIgnoreCase(base, "powershell.exe")) return .powershell;
        return .auto;
    }
};

pub const ReadChunk = struct {
    bytes: []const u8,
    owned: bool = false,
};

var hidden_console_ready = false;

fn ensureHiddenConsole() void {
    if (hidden_console_ready) return;
    hidden_console_ready = true;
    _ = SetConsoleOutputCP(65001);
    _ = SetConsoleCP(65001);
    if (AllocConsole() != 0) {
        _ = SetConsoleOutputCP(65001);
        _ = SetConsoleCP(65001);
        if (GetConsoleWindow()) |con_hwnd| {
            if (loadShowWindow()) |show_window| {
                _ = show_window(con_hwnd, 0);
            }
        }
    }
}

fn loadShowWindow() ?*const fn (windows.HWND, i32) callconv(.winapi) BOOL {
    const user32_name: [*:0]const u16 = &[_:0]u16{ 'u', 's', 'e', 'r', '3', '2', '.', 'd', 'l', 'l' };
    const module = windows.kernel32.LoadLibraryW(user32_name) orelse return null;
    const symbol = windows.kernel32.GetProcAddress(module, "ShowWindow") orelse return null;
    return @ptrCast(symbol);
}

const ReaderState = struct {
    buf: [256 * 1024]u8 = undefined,
    write_pos: u32 = 0,
    read_pos: u32 = 0,
    stop: i32 = 0,
    event: HANDLE = INVALID_HANDLE,
    pipe: HANDLE = INVALID_HANDLE,
};

fn readerThreadFn(param: ?*anyopaque) callconv(.winapi) DWORD {
    const state: *ReaderState = @ptrCast(@alignCast(param));
    var tmp: [65536]u8 = undefined;
    const read_evt = CreateEventW(null, 1, 0, null);
    if (read_evt == INVALID_HANDLE) return 1;
    defer _ = CloseHandle(read_evt);

    while (@atomicLoad(i32, &state.stop, .seq_cst) == 0) {
        var overlapped = OVERLAPPED{ .hEvent = read_evt };
        _ = ResetEvent(read_evt);
        var bytes_read: DWORD = 0;
        const ok = ReadFile(state.pipe, &tmp, @intCast(tmp.len), &bytes_read, @ptrCast(&overlapped));
        if (ok == 0) {
            if (windows.kernel32.GetLastError() != .IO_PENDING) break;
            _ = WaitForSingleObject(read_evt, INFINITE);
            if (GetOverlappedResult(state.pipe, &overlapped, &bytes_read, 0) == 0) break;
        }
        if (bytes_read == 0) break;

        const n: u32 = bytes_read;
        const buf_len: u32 = @intCast(state.buf.len);
        var w = @atomicLoad(u32, &state.write_pos, .seq_cst);
        var remaining = n;
        var src_off: u32 = 0;
        while (remaining > 0) {
            const pos = w % buf_len;
            const chunk = @min(remaining, buf_len - pos);
            @memcpy(state.buf[pos..][0..chunk], tmp[src_off..][0..chunk]);
            w +%= chunk;
            src_off += chunk;
            remaining -= chunk;
        }
        @atomicStore(u32, &state.write_pos, w, .seq_cst);
        _ = SetEvent(state.event);
    }
    return 0;
}

pub const Pty = struct {
    allocator: std.mem.Allocator,
    pipe_out_read: HANDLE,
    pipe_in_write: HANDLE,
    process: HANDLE,
    hpc: HPCON,
    attr_list_buf: []align(8) u8,
    read_event: HANDLE,
    reader_thread: HANDLE = INVALID_HANDLE,
    reader_state: ?*ReaderState = null,
    exit_status: ?u8 = null,

    pub fn spawn(allocator: std.mem.Allocator, config: SpawnConfig) !Pty {
        var pty_in_read: HANDLE = INVALID_HANDLE;
        var pty_in_write: HANDLE = INVALID_HANDLE;
        if (CreatePipe(&pty_in_read, &pty_in_write, null, 0) == 0) return error.CreatePipeFailed;
        errdefer {
            _ = CloseHandle(pty_in_read);
            _ = CloseHandle(pty_in_write);
        }
        _ = SetHandleInformation(pty_in_write, HANDLE_FLAG_INHERIT, 0);

        const out_pipe = createOverlappedOutputPipe() orelse return error.CreatePipeFailed;
        errdefer {
            _ = CloseHandle(out_pipe.read);
            _ = CloseHandle(out_pipe.write);
            _ = CloseHandle(out_pipe.event);
        }

        const size = COORD{
            .x = @intCast(config.cols),
            .y = @intCast(config.rows),
        };

        const shell = if (config.shell == .auto) ShellType.detect(config.argv) else config.shell;
        const use_passthrough = shell != .cmd and shell != .auto;
        var hpc: HPCON = undefined;
        const passthrough_ok = use_passthrough and CreatePseudoConsole(size, pty_in_read, out_pipe.write, PSEUDOCONSOLE_PASSTHROUGH, &hpc) == S_OK;
        if (!passthrough_ok and CreatePseudoConsole(size, pty_in_read, out_pipe.write, 0, &hpc) != S_OK) {
            return error.CreatePseudoConsoleFailed;
        }
        errdefer ClosePseudoConsole(hpc);

        var attr_list_size: usize = 0;
        _ = InitializeProcThreadAttributeList(null, 1, 0, &attr_list_size);
        const attr_buf = try allocator.alignedAlloc(u8, .@"8", attr_list_size);
        errdefer allocator.free(attr_buf);

        const attr_list: LPPROC_THREAD_ATTRIBUTE_LIST = @ptrCast(attr_buf.ptr);
        if (InitializeProcThreadAttributeList(attr_list, 1, 0, &attr_list_size) == 0) {
            return error.InitAttrListFailed;
        }
        errdefer DeleteProcThreadAttributeList(attr_list);

        if (UpdateProcThreadAttribute(
            attr_list,
            0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            @ptrCast(hpc),
            @sizeOf(HPCON),
            null,
            null,
        ) == 0) {
            return error.UpdateAttrFailed;
        }

        _ = SetConsoleOutputCP(65001);
        _ = SetConsoleCP(65001);
        setEnvW("TERM", "xterm-256color");
        setEnvW("COLORTERM", "truecolor");
        setEnvW("TERM_PROGRAM", "fmus");
        setEnvW("FMUS_TERMINAL", "1");

        ensureHiddenConsole();

        const cmd_line = try buildCommandLine(allocator, config.argv);
        defer freeWideZ(allocator, cmd_line);

        const cwd_wide = try maybeWide(allocator, config.cwd);
        defer if (cwd_wide) |buf| freeWideZ(allocator, buf);

        var startup = std.mem.zeroes(STARTUPINFOEXW);
        startup.StartupInfo.cb = @sizeOf(STARTUPINFOEXW);
        startup.lpAttributeList = attr_list;

        var process_info: PROCESS_INFORMATION = undefined;
        if (CreateProcessW(
            null,
            cmd_line.ptr,
            null,
            null,
            0,
            EXTENDED_STARTUPINFO_PRESENT,
            null,
            if (cwd_wide) |buf| @ptrCast(buf.ptr) else null,
            &startup,
            &process_info,
        ) == 0) {
            return error.CreateProcessFailed;
        }

        _ = CloseHandle(process_info.hThread);
        _ = CloseHandle(pty_in_read);
        _ = CloseHandle(out_pipe.write);

        const rs = try allocator.create(ReaderState);
        rs.* = .{
            .event = out_pipe.event,
            .pipe = out_pipe.read,
        };
        errdefer allocator.destroy(rs);

        const reader_thread = CreateThread(null, 0, &readerThreadFn, @ptrCast(rs), 0, null) orelse return error.CreateThreadFailed;

        return .{
            .allocator = allocator,
            .pipe_out_read = out_pipe.read,
            .pipe_in_write = pty_in_write,
            .process = process_info.hProcess,
            .hpc = hpc,
            .attr_list_buf = attr_buf,
            .read_event = out_pipe.event,
            .reader_thread = reader_thread,
            .reader_state = rs,
        };
    }

    pub fn deinit(self: *Pty) void {
        if (self.reader_state) |rs| {
            @atomicStore(i32, &rs.stop, 1, .seq_cst);
        }
        if (self.pipe_in_write != INVALID_HANDLE) _ = CloseHandle(self.pipe_in_write);
        if (self.pipe_out_read != INVALID_HANDLE) _ = CloseHandle(self.pipe_out_read);
        if (self.reader_thread != INVALID_HANDLE) {
            _ = WaitForSingleObject(self.reader_thread, 5000);
            _ = CloseHandle(self.reader_thread);
        }
        if (self.read_event != INVALID_HANDLE) _ = CloseHandle(self.read_event);
        if (self.process != INVALID_HANDLE) _ = CloseHandle(self.process);
        ClosePseudoConsole(self.hpc);
        if (self.reader_state) |rs| self.allocator.destroy(rs);
        if (self.attr_list_buf.len > 0) {
            DeleteProcThreadAttributeList(@ptrCast(self.attr_list_buf.ptr));
            self.allocator.free(self.attr_list_buf);
            self.attr_list_buf = &.{};
        }
        self.pipe_in_write = INVALID_HANDLE;
        self.pipe_out_read = INVALID_HANDLE;
        self.read_event = INVALID_HANDLE;
        self.process = INVALID_HANDLE;
        self.reader_thread = INVALID_HANDLE;
        self.reader_state = null;
    }

    pub fn readAvailable(self: *Pty, allocator: std.mem.Allocator) !?ReadChunk {
        if (self.reader_state) |rs| {
            const data = consumeReaderData(rs) orelse return null;
            const owned = try allocator.dupe(u8, data);
            return .{
                .bytes = owned,
                .owned = true,
            };
        }

        var avail: DWORD = 0;
        if (PeekNamedPipe(self.pipe_out_read, null, 0, null, &avail, null) == 0) {
            return error.ReadFailed;
        }
        if (avail == 0) return null;

        const buffer = try allocator.alloc(u8, avail);
        errdefer allocator.free(buffer);

        const n = try self.readSync(buffer);
        return .{
            .bytes = buffer[0..n],
            .owned = true,
        };
    }

    fn readSync(self: *Pty, buffer: []u8) !usize {
        _ = ResetEvent(self.read_event);
        var overlapped = OVERLAPPED{ .hEvent = self.read_event };
        var bytes_read: DWORD = 0;
        if (ReadFile(self.pipe_out_read, buffer.ptr, @intCast(buffer.len), &bytes_read, @ptrCast(&overlapped)) != 0) {
            return bytes_read;
        }
        if (windows.kernel32.GetLastError() != .IO_PENDING) return error.ReadFailed;
        _ = WaitForSingleObject(self.read_event, INFINITE);
        if (GetOverlappedResult(self.pipe_out_read, &overlapped, &bytes_read, 0) == 0) return error.ReadFailed;
        return bytes_read;
    }

    pub fn writeAll(self: *Pty, bytes: []const u8) !void {
        var written: DWORD = 0;
        if (WriteFile(self.pipe_in_write, bytes.ptr, @intCast(bytes.len), &written, null) == 0) {
            return error.WriteFailed;
        }
        if (written != bytes.len) return error.ShortWrite;
    }

    pub fn resize(self: *Pty, rows: u16, cols: u16) !void {
        const size = COORD{
            .x = @intCast(cols),
            .y = @intCast(rows),
        };
        if (ResizePseudoConsole(self.hpc, size) != S_OK) return error.ResizeFailed;
    }

    pub fn childExited(self: *Pty) bool {
        if (self.exit_status != null) return true;
        var code: DWORD = 0;
        if (GetExitCodeProcess(self.process, &code) == 0) return true;
        if (code == STILL_ACTIVE) return false;
        self.exit_status = @intCast(code & 0xff);
        return true;
    }

    pub fn exitCode(self: *Pty) ?u8 {
        _ = self.childExited();
        return self.exit_status;
    }

    pub fn wait(self: *Pty) void {
        _ = WaitForSingleObject(self.process, INFINITE);
        _ = self.childExited();
    }
};

fn consumeReaderData(rs: *ReaderState) ?[]const u8 {
    const S = struct {
        var out_buf: [65536]u8 = undefined;
    };
    const buf_len: u32 = @intCast(rs.buf.len);
    const w = @atomicLoad(u32, &rs.write_pos, .seq_cst);
    var r = @atomicLoad(u32, &rs.read_pos, .seq_cst);
    if (w == r) return null;

    const avail = (w -% r) % buf_len;
    const n = @min(avail, @as(u32, @intCast(S.out_buf.len)));
    var remaining = n;
    var dst_off: u32 = 0;
    while (remaining > 0) {
        const pos = r % buf_len;
        const chunk = @min(remaining, buf_len - pos);
        @memcpy(S.out_buf[dst_off..][0..chunk], rs.buf[pos..][0..chunk]);
        r +%= chunk;
        dst_off += chunk;
        remaining -= chunk;
    }
    @atomicStore(u32, &rs.read_pos, r, .seq_cst);
    return S.out_buf[0..n];
}

fn createOverlappedOutputPipe() ?struct { read: HANDLE, write: HANDLE, event: HANDLE } {
    const pid = GetCurrentProcessId();
    const seq = blk: {
        const S = struct {
            var counter: u32 = 0;
        };
        break :blk @atomicRmw(u32, &S.counter, .Add, 1, .seq_cst);
    };

    var name_ascii: [128]u8 = undefined;
    const name = std.fmt.bufPrint(&name_ascii, "\\\\.\\pipe\\fmus-terminal-{d}-{d}", .{ pid, seq }) catch return null;
    var name_wide: [128:0]u16 = undefined;
    for (name, 0..) |ch, i| name_wide[i] = ch;
    name_wide[name.len] = 0;

    const read_handle = CreateNamedPipeW(
        name_wide[0..name.len :0],
        PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE_WAIT,
        1,
        0,
        65536,
        0,
        null,
    );
    if (read_handle == INVALID_HANDLE) return null;

    const write_handle = CreateFileW(
        name_wide[0..name.len :0],
        WIN_GENERIC_WRITE,
        0,
        null,
        OPEN_EXISTING,
        0,
        null,
    );
    if (write_handle == INVALID_HANDLE) {
        _ = CloseHandle(read_handle);
        return null;
    }

    const event = CreateEventW(null, 1, 0, null);
    if (@intFromPtr(event) == 0) {
        _ = CloseHandle(read_handle);
        _ = CloseHandle(write_handle);
        return null;
    }

    return .{
        .read = read_handle,
        .write = write_handle,
        .event = event,
    };
}

fn buildCommandLine(allocator: std.mem.Allocator, argv: []const []const u8) ![:0]u16 {
    if (argv.len == 0) return error.InvalidCommandLine;

    if (isBatchScript(argv[0])) {
        const script_path = try utf8ToWideZ(allocator, argv[0]);
        defer allocator.free(script_path);
        return try argvToScriptCommandLineWindows(allocator, script_path, argv[1..]);
    }

    return try argvToCommandLineWindows(allocator, argv);
}

fn isBatchScript(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".bat") or std.ascii.endsWithIgnoreCase(path, ".cmd");
}

fn argvToCommandLineWindows(allocator: std.mem.Allocator, argv: []const []const u8) ![:0]u16 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    if (argv.len != 0) {
        const arg0 = argv[0];
        var needs_quotes = arg0.len == 0;
        for (arg0) |c| {
            if (c <= ' ') {
                needs_quotes = true;
            } else if (c == '"') {
                return error.InvalidCommandLine;
            }
        }
        if (needs_quotes) {
            try buf.append('"');
            try buf.appendSlice(arg0);
            try buf.append('"');
        } else {
            try buf.appendSlice(arg0);
        }

        for (argv[1..]) |arg| {
            try buf.append(' ');

            needs_quotes = for (arg) |c| {
                if (c <= ' ' or c == '"') break true;
            } else arg.len == 0;
            if (!needs_quotes) {
                try buf.appendSlice(arg);
                continue;
            }

            try buf.append('"');
            var backslash_count: usize = 0;
            for (arg) |byte| {
                switch (byte) {
                    '\\' => backslash_count += 1,
                    '"' => {
                        try buf.appendNTimes('\\', backslash_count * 2 + 1);
                        try buf.append('"');
                        backslash_count = 0;
                    },
                    else => {
                        try buf.appendNTimes('\\', backslash_count);
                        try buf.append(byte);
                        backslash_count = 0;
                    },
                }
            }
            try buf.appendNTimes('\\', backslash_count * 2);
            try buf.append('"');
        }
    }

    return try utf8ToWideZ(allocator, buf.items);
}

fn argvToScriptCommandLineWindows(
    allocator: std.mem.Allocator,
    script_path: []const u16,
    script_args: []const []const u8,
) ![:0]u16 {
    var buf = try std.array_list.Managed(u8).initCapacity(allocator, 64);
    defer buf.deinit();

    buf.appendSliceAssumeCapacity("cmd.exe /d /e:ON /v:OFF /c \"");
    buf.appendAssumeCapacity('"');

    if (std.mem.indexOfAny(u16, script_path, &[_]u16{ '\\', '/' }) == null) {
        try buf.appendSlice(".\\");
    }
    try std.unicode.wtf16LeToWtf8ArrayList(&buf, script_path);
    buf.appendAssumeCapacity('"');

    for (script_args) |arg| {
        if (std.mem.indexOfAny(u8, arg, "\x00\r\n") != null) {
            return error.InvalidCommandLine;
        }

        try buf.append(' ');

        var needs_quotes = arg.len == 0 or arg[arg.len - 1] == '\\';
        if (!needs_quotes) {
            for (arg) |c| {
                switch (c) {
                    'A'...'Z', 'a'...'z', '0'...'9', '#', '$', '*', '+', '-', '.', '/', ':', '?', '@', '\\', '_' => {},
                    else => {
                        needs_quotes = true;
                        break;
                    },
                }
            }
        }
        if (needs_quotes) try buf.append('"');

        var backslashes: usize = 0;
        for (arg) |c| {
            switch (c) {
                '\\' => backslashes += 1,
                '"' => {
                    try buf.appendNTimes('\\', backslashes);
                    try buf.append('"');
                    backslashes = 0;
                },
                '%' => {
                    try buf.appendSlice("%%cd:~,");
                    backslashes = 0;
                },
                else => backslashes = 0,
            }
            try buf.append(c);
        }
        if (needs_quotes) {
            try buf.appendNTimes('\\', backslashes);
            try buf.append('"');
        }
    }

    try buf.append('"');
    return try utf8ToWideZ(allocator, buf.items);
}

fn maybeWide(allocator: std.mem.Allocator, value: ?[]const u8) !?[:0]u16 {
    if (value) |slice| return try utf8ToWideZ(allocator, slice);
    return null;
}

fn utf8ToWideZ(allocator: std.mem.Allocator, value: []const u8) ![:0]u16 {
    const len = try std.unicode.calcUtf16LeLen(value);
    const tmp = try allocator.alloc(u16, len + 1);
    _ = try std.unicode.utf8ToUtf16Le(tmp[0..len], value);
    tmp[len] = 0;
    return tmp[0..len :0];
}

fn freeWideZ(allocator: std.mem.Allocator, value: [:0]u16) void {
    allocator.free(value[0 .. value.len + 1]);
}

fn setEnvW(comptime name: []const u8, comptime value: []const u8) void {
    const name_w = comptime toUtf16Literal(name);
    const value_w = comptime toUtf16Literal(value);
    _ = SetEnvironmentVariableW(&name_w, &value_w);
}

fn toUtf16Literal(comptime s: []const u8) [s.len:0]u16 {
    comptime {
        var result: [s.len:0]u16 = undefined;
        for (s, 0..) |ch, i| result[i] = ch;
        return result;
    }
}

test "windows command line builder quotes node eval args" {
    const allocator = std.testing.allocator;
    const line = try buildCommandLine(allocator, &.{
        "node.exe",
        "-e",
        "console.log(\"hello world\")",
    });
    defer freeWideZ(allocator, line);

    const roundtrip = try std.unicode.wtf16LeToWtf8Alloc(allocator, line);
    defer allocator.free(roundtrip);

    try std.testing.expectEqualStrings(
        "node.exe -e \"console.log(\\\"hello world\\\")\"",
        roundtrip,
    );
}

test "windows command line builder wraps batch scripts through cmd" {
    const allocator = std.testing.allocator;
    const line = try buildCommandLine(allocator, &.{
        "C:\\work\\bin\\cc.bat",
    });
    defer freeWideZ(allocator, line);

    const roundtrip = try std.unicode.wtf16LeToWtf8Alloc(allocator, line);
    defer allocator.free(roundtrip);

    try std.testing.expect(std.mem.startsWith(u8, roundtrip, "cmd.exe /d /e:ON /v:OFF /c "));
    try std.testing.expect(std.mem.indexOf(u8, roundtrip, "C:\\work\\bin\\cc.bat") != null);
}
