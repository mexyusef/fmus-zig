const std = @import("std");
const socket = @import("socket.zig");
const http_server = @import("http_server.zig");

pub const Role = enum {
    client,
    server,
};

pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,

    pub fn isControl(self: Opcode) bool {
        return switch (self) {
            .close, .ping, .pong => true,
            else => false,
        };
    }
};

pub const CloseCode = enum(u16) {
    normal = 1000,
    going_away = 1001,
    protocol_error = 1002,
    unsupported_data = 1003,
    no_status = 1005,
    abnormal = 1006,
    invalid_payload = 1007,
    policy_violation = 1008,
    message_too_big = 1009,
    mandatory_extension = 1010,
    internal_error = 1011,
    tls_handshake = 1015,
    _,
};

pub const MessageType = enum {
    text,
    binary,
};

pub const Config = struct {
    max_payload_len: u64 = 16 * 1024 * 1024,
};

pub const Error = error{
    InvalidWebSocketUrl,
    InvalidWebSocketPath,
    UnsupportedSecureWebSocket,
    InvalidUpgradeResponse,
    InvalidUpgradeRequest,
    UpgradeRejected,
    MissingUpgradeHeader,
    MissingConnectionHeader,
    MissingAcceptHeader,
    MissingHostHeader,
    MissingKeyHeader,
    MissingVersionHeader,
    AcceptMismatch,
    InvalidStatusLine,
    HeaderTooLarge,
    ReservedFlags,
    InvalidOpcode,
    ControlFragmented,
    ControlTooLarge,
    MessageTooLarge,
    UnexpectedMask,
    MissingMask,
    Utf8Expected,
    InvalidClosePayload,
    UnexpectedContinuation,
    NestedFragment,
};

pub const Url = struct {
    secure: bool,
    host: []const u8,
    port: ?u16,
    path: []const u8,
    query: []const u8,

    pub fn parse(input: []const u8) !Url {
        const secure = std.mem.startsWith(u8, input, "wss://");
        const plain = std.mem.startsWith(u8, input, "ws://");
        if (!secure and !plain) return Error.InvalidWebSocketUrl;

        const rest = input[if (secure) 6 else 5 ..];
        if (rest.len == 0) return Error.InvalidWebSocketUrl;

        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        const host_port = rest[0..slash];
        if (host_port.len == 0) return Error.InvalidWebSocketUrl;

        const path_and_query = if (slash < rest.len) rest[slash..] else "/";
        const qmark = std.mem.indexOfScalar(u8, path_and_query, '?');
        const path = if (qmark) |idx| path_and_query[0..idx] else path_and_query;
        const query = if (qmark) |idx| path_and_query[idx + 1 ..] else "";
        if (path.len == 0 or path[0] != '/') return Error.InvalidWebSocketPath;

        if (std.mem.lastIndexOfScalar(u8, host_port, ':')) |idx| {
            if (idx == 0 or idx == host_port.len - 1) return Error.InvalidWebSocketUrl;
            return .{
                .secure = secure,
                .host = host_port[0..idx],
                .port = try std.fmt.parseInt(u16, host_port[idx + 1 ..], 10),
                .path = path,
                .query = query,
            };
        }

        return .{
            .secure = secure,
            .host = host_port,
            .port = null,
            .path = path,
            .query = query,
        };
    }

    pub fn portOrDefault(self: Url) u16 {
        return self.port orelse if (self.secure) 443 else 80;
    }

    pub fn targetAlloc(self: Url, allocator: std.mem.Allocator) ![]u8 {
        if (self.query.len == 0) return allocator.dupe(u8, self.path);
        return std.fmt.allocPrint(allocator, "{s}?{s}", .{ self.path, self.query });
    }
};

pub const AcceptKey = [28]u8;
pub const ClientKey = [24]u8;

pub const Mask = struct {
    key: [4]u8,
    offset: usize = 0,

    pub fn init(key: [4]u8) Mask {
        return .{ .key = key };
    }

    pub fn apply(self: *Mask, bytes: []u8) void {
        for (bytes, 0..) |*byte, idx| {
            byte.* ^= self.key[(self.offset + idx) & 3];
        }
        self.offset = (self.offset + bytes.len) & 3;
    }
};

pub fn makeClientKey(random: std.Random, out: *ClientKey) void {
    var raw: [16]u8 = undefined;
    random.bytes(&raw);
    _ = std.base64.standard.Encoder.encode(out, &raw);
}

pub fn computeAcceptKey(client_key: []const u8, out: *AcceptKey) []const u8 {
    var sha: [20]u8 = undefined;
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(client_key);
    hasher.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    hasher.final(&sha);
    _ = std.base64.standard.Encoder.encode(out, &sha);
    return out;
}

pub const UpgradeResponse = struct {
    key: []const u8,
    protocol: ?[]const u8 = null,
    extra_headers: []const Header = &.{},

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn write(self: UpgradeResponse, writer: anytype) !void {
        var accept_buf: AcceptKey = undefined;
        const accept = computeAcceptKey(self.key, &accept_buf);

        try writer.writeAll("HTTP/1.1 101 Switching Protocols\r\n");
        try writer.writeAll("Upgrade: websocket\r\n");
        try writer.writeAll("Connection: Upgrade\r\n");
        try writer.print("Sec-WebSocket-Accept: {s}\r\n", .{accept});
        if (self.protocol) |protocol| {
            try writer.print("Sec-WebSocket-Protocol: {s}\r\n", .{protocol});
        }
        for (self.extra_headers) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
        }
        try writer.writeAll("\r\n");
    }
};

pub const UpgradeRequest = struct {
    host: []const u8,
    target: []const u8,
    key: []const u8,
    protocol: ?[]const u8 = null,
    origin: ?[]const u8 = null,
    extra_headers: []const Header = &.{},

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn write(self: UpgradeRequest, writer: anytype) !void {
        try writer.print("GET {s} HTTP/1.1\r\n", .{self.target});
        try writer.print("Host: {s}\r\n", .{self.host});
        try writer.writeAll("Upgrade: websocket\r\n");
        try writer.writeAll("Connection: Upgrade\r\n");
        try writer.writeAll("Sec-WebSocket-Version: 13\r\n");
        try writer.print("Sec-WebSocket-Key: {s}\r\n", .{self.key});
        if (self.protocol) |protocol| {
            try writer.print("Sec-WebSocket-Protocol: {s}\r\n", .{protocol});
        }
        if (self.origin) |origin| {
            try writer.print("Origin: {s}\r\n", .{origin});
        }
        for (self.extra_headers) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
        }
        try writer.writeAll("\r\n");
    }
};

pub const UpgradeInfo = struct {
    status_code: u16,
    accept: []const u8,
    protocol: ?[]const u8 = null,
};

pub const ReadHandshakeResult = struct {
    request: HandshakeRequest,
    raw_len: usize,
};

pub const HandshakeRequest = struct {
    method: []const u8,
    target: []const u8,
    host: []const u8,
    key: []const u8,
    version: []const u8,
    raw_headers: []const u8,
    protocol_header: ?[]const u8 = null,

    pub fn parse(raw: []const u8) !HandshakeRequest {
        const sep = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return Error.InvalidUpgradeRequest;
        const head = raw[0..sep];
        var lines = std.mem.splitSequence(u8, head, "\r\n");
        const request_line = lines.next() orelse return Error.InvalidUpgradeRequest;

        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return Error.InvalidUpgradeRequest;
        const target = parts.next() orelse return Error.InvalidUpgradeRequest;
        _ = parts.next() orelse return Error.InvalidUpgradeRequest;

        var host: ?[]const u8 = null;
        var key: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var protocol_header: ?[]const u8 = null;
        var saw_upgrade = false;
        var saw_connection = false;

        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const name = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

            if (std.ascii.eqlIgnoreCase(name, "host")) {
                host = value;
            } else if (std.ascii.eqlIgnoreCase(name, "upgrade")) {
                if (std.ascii.eqlIgnoreCase(value, "websocket")) saw_upgrade = true;
            } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
                if (containsTokenIgnoreCase(value, "upgrade")) saw_connection = true;
            } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-key")) {
                key = value;
            } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-version")) {
                version = value;
            } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-protocol")) {
                protocol_header = value;
            }
        }

        if (!std.ascii.eqlIgnoreCase(method, "GET")) return Error.InvalidUpgradeRequest;
        if (!saw_upgrade) return Error.MissingUpgradeHeader;
        if (!saw_connection) return Error.MissingConnectionHeader;

        return .{
            .method = method,
            .target = target,
            .host = host orelse return Error.MissingHostHeader,
            .key = key orelse return Error.MissingKeyHeader,
            .version = version orelse return Error.MissingVersionHeader,
            .raw_headers = head,
            .protocol_header = protocol_header,
        };
    }

    pub fn protocols(self: HandshakeRequest, allocator: std.mem.Allocator) ![][]const u8 {
        if (self.protocol_header == null) return allocator.alloc([]const u8, 0);
        var list = std.ArrayList([]const u8).empty;
        errdefer list.deinit(allocator);
        var it = std.mem.splitScalar(u8, self.protocol_header.?, ',');
        while (it.next()) |part| {
            try list.append(allocator, std.mem.trim(u8, part, " \t"));
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn acceptsProtocol(self: HandshakeRequest, protocol: []const u8) bool {
        if (self.protocol_header == null) return false;
        var it = std.mem.splitScalar(u8, self.protocol_header.?, ',');
        while (it.next()) |part| {
            if (std.mem.eql(u8, std.mem.trim(u8, part, " \t"), protocol)) return true;
        }
        return false;
    }

    pub fn writeResponse(self: HandshakeRequest, writer: anytype, protocol: ?[]const u8, extra_headers: []const UpgradeResponse.Header) !void {
        try (UpgradeResponse{
            .key = self.key,
            .protocol = protocol,
            .extra_headers = extra_headers,
        }).write(writer);
    }
};

pub fn verifyUpgradeResponse(response: []const u8, expected_key: []const u8) !UpgradeInfo {
    const sep = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return Error.InvalidUpgradeResponse;
    const headers_block = response[0..sep];
    var lines = std.mem.splitSequence(u8, headers_block, "\r\n");
    const status_line = lines.next() orelse return Error.InvalidStatusLine;

    var status_parts = std.mem.splitScalar(u8, status_line, ' ');
    const http_version = status_parts.next() orelse return Error.InvalidStatusLine;
    _ = http_version;
    const status_raw = status_parts.next() orelse return Error.InvalidStatusLine;
    const status_code = try std.fmt.parseInt(u16, status_raw, 10);
    if (status_code != 101) return Error.UpgradeRejected;

    var saw_upgrade = false;
    var saw_connection = false;
    var accept_header: ?[]const u8 = null;
    var protocol_header: ?[]const u8 = null;

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        if (std.ascii.eqlIgnoreCase(name, "upgrade")) {
            if (std.ascii.eqlIgnoreCase(value, "websocket")) saw_upgrade = true;
        } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
            if (containsTokenIgnoreCase(value, "upgrade")) saw_connection = true;
        } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-accept")) {
            accept_header = value;
        } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-protocol")) {
            protocol_header = value;
        }
    }

    if (!saw_upgrade) return Error.MissingUpgradeHeader;
    if (!saw_connection) return Error.MissingConnectionHeader;
    const accept = accept_header orelse return Error.MissingAcceptHeader;

    var expected_accept_buf: AcceptKey = undefined;
    const expected_accept = computeAcceptKey(expected_key, &expected_accept_buf);
    if (!std.mem.eql(u8, accept, expected_accept)) return Error.AcceptMismatch;

    return .{
        .status_code = status_code,
        .accept = accept,
        .protocol = protocol_header,
    };
}

pub fn readHandshakeRequest(handle: std.net.Stream.Handle, buffer: []u8) !ReadHandshakeResult {
    var used: usize = 0;
    while (std.mem.indexOf(u8, buffer[0..used], "\r\n\r\n") == null) {
        if (used == buffer.len) return Error.HeaderTooLarge;
        const amt = try socket.recv(handle, buffer[used..]);
        if (amt == 0) return error.EndOfStream;
        used += amt;
    }
    return .{
        .request = try HandshakeRequest.parse(buffer[0..used]),
        .raw_len = used,
    };
}

pub const FrameOptions = struct {
    fin: bool = true,
    opcode: Opcode = .text,
    masked: bool = false,
    mask_key: ?[4]u8 = null,
};

pub const FrameHeader = struct {
    fin: bool = true,
    rsv1: bool = false,
    rsv2: bool = false,
    rsv3: bool = false,
    opcode: Opcode = .text,
    masked: bool = false,
    payload_len: u64 = 0,
    mask_key: ?[4]u8 = null,

    pub const Buffer = struct {
        bytes: [14]u8 = undefined,
        len: usize = 0,

        pub fn init(header: FrameHeader) Buffer {
            var out: Buffer = .{};
            out.len = encodeFrameHeader(header, &out.bytes);
            return out;
        }

        pub fn slice(self: *const Buffer) []const u8 {
            return self.bytes[0..self.len];
        }
    };
};

fn encodeFrameHeader(header: FrameHeader, out: *[14]u8) usize {
    out[0] = (if (header.fin) @as(u8, 0x80) else 0) |
        (if (header.rsv1) @as(u8, 0x40) else 0) |
        (if (header.rsv2) @as(u8, 0x20) else 0) |
        (if (header.rsv3) @as(u8, 0x10) else 0) |
        @intFromEnum(header.opcode);

    var idx: usize = 2;
    const mask_bit: u8 = if (header.masked) 0x80 else 0;
    if (header.payload_len < 126) {
        out[1] = mask_bit | @as(u8, @intCast(header.payload_len));
    } else if (header.payload_len <= std.math.maxInt(u16)) {
        out[1] = mask_bit | 126;
        std.mem.writeInt(u16, out[2..4], @as(u16, @intCast(header.payload_len)), .big);
        idx = 4;
    } else {
        out[1] = mask_bit | 127;
        std.mem.writeInt(u64, out[2..10], header.payload_len, .big);
        idx = 10;
    }

    if (header.masked) {
        const key = header.mask_key orelse [4]u8{ 0, 0, 0, 0 };
        @memcpy(out[idx .. idx + 4], &key);
        idx += 4;
    }
    return idx;
}

pub fn writeFrame(writer: anytype, payload: []const u8, options: FrameOptions) !void {
    const header = FrameHeader{
        .fin = options.fin,
        .opcode = options.opcode,
        .masked = options.masked,
        .payload_len = payload.len,
        .mask_key = options.mask_key,
    };
    var header_buf = FrameHeader.Buffer.init(header);
    try writer.writeAll(header_buf.slice());

    if (options.masked) {
        const key = options.mask_key orelse [4]u8{ 0, 0, 0, 0 };
        var masked = Mask.init(key);
        var tmp: [1024]u8 = undefined;
        var offset: usize = 0;
        while (offset < payload.len) {
            const end = @min(offset + tmp.len, payload.len);
            @memcpy(tmp[0 .. end - offset], payload[offset..end]);
            masked.apply(tmp[0 .. end - offset]);
            try writer.writeAll(tmp[0 .. end - offset]);
            offset = end;
        }
        return;
    }

    try writer.writeAll(payload);
}

pub fn writeClose(writer: anytype, code: CloseCode, reason: []const u8, masked: bool) !void {
    var payload: [125]u8 = undefined;
    std.mem.writeInt(u16, payload[0..2], @intFromEnum(code), .big);
    @memcpy(payload[2 .. 2 + reason.len], reason);
    try writeFrame(writer, payload[0 .. 2 + reason.len], .{
        .opcode = .close,
        .masked = masked,
    });
}

pub const Parser = struct {
    role: Role,
    max_payload_len: u64 = 16 * 1024 * 1024,
    state: State = .header,
    pending_header: FrameHeader = .{},
    payload_remaining: usize = 0,
    current_mask: ?Mask = null,
    frame_end_pending: bool = false,
    header_buf: [14]u8 = undefined,
    header_len: usize = 0,
    need_bytes: usize = 2,

    const State = enum {
        header,
        payload,
    };

    pub const Event = union(enum) {
        frame_header: FrameHeader,
        payload: []u8,
        frame_end: void,
        need_more: void,
    };

    pub const Result = struct {
        consumed: usize,
        event: Event,
    };

    pub fn init(role: Role, options: Config) Parser {
        return .{
            .role = role,
            .max_payload_len = options.max_payload_len,
        };
    }

    pub fn feed(self: *Parser, bytes: []u8) !Result {
        if (self.frame_end_pending) {
            self.frame_end_pending = false;
            self.resetHeaderState();
            return .{ .consumed = 0, .event = .frame_end };
        }
        switch (self.state) {
            .header => return self.feedHeader(bytes),
            .payload => return self.feedPayload(bytes),
        }
    }

    fn feedHeader(self: *Parser, bytes: []u8) !Result {
        const copied = self.copyIntoHeader(bytes);
        if (self.header_len < self.need_bytes) {
            return .{ .consumed = copied, .event = .need_more };
        }

        const parsed = try self.tryParseHeader();
        if (!parsed) {
            return .{ .consumed = copied, .event = .need_more };
        }

        self.state = .payload;
        return .{
            .consumed = copied,
            .event = .{ .frame_header = self.pending_header },
        };
    }

    fn feedPayload(self: *Parser, bytes: []u8) !Result {
        if (self.payload_remaining == 0) {
            self.frame_end_pending = false;
            self.resetHeaderState();
            return .{ .consumed = 0, .event = .frame_end };
        }
        if (bytes.len == 0) {
            return .{ .consumed = 0, .event = .need_more };
        }

        const take = @min(bytes.len, self.payload_remaining);
        const payload = bytes[0..take];
        if (self.current_mask) |*mask| {
            mask.apply(payload);
        }
        self.payload_remaining -= take;
        if (self.payload_remaining == 0) {
            self.frame_end_pending = true;
        }

        return .{
            .consumed = take,
            .event = .{ .payload = payload },
        };
    }

    fn copyIntoHeader(self: *Parser, bytes: []u8) usize {
        const remaining = self.need_bytes - self.header_len;
        const take = @min(bytes.len, remaining);
        @memcpy(self.header_buf[self.header_len .. self.header_len + take], bytes[0..take]);
        self.header_len += take;
        return take;
    }

    fn tryParseHeader(self: *Parser) !bool {
        if (self.header_len < 2) return false;

        const b0 = self.header_buf[0];
        const b1 = self.header_buf[1];
        const masked = (b1 & 0x80) != 0;
        var payload_len: u64 = b1 & 0x7F;
        var needed: usize = 2;

        if ((b0 & 0x70) != 0) return Error.ReservedFlags;

        const opcode: Opcode = @enumFromInt(@as(u4, @truncate(b0 & 0x0F)));
        if (!isKnownOpcode(opcode)) return Error.InvalidOpcode;
        if (opcode.isControl() and (b0 & 0x80) == 0) return Error.ControlFragmented;

        if (payload_len == 126) needed += 2 else if (payload_len == 127) needed += 8;
        if (masked) needed += 4;
        self.need_bytes = needed;
        if (self.header_len < needed) return false;

        var idx: usize = 2;
        if (payload_len == 126) {
            payload_len = std.mem.readInt(u16, self.header_buf[idx..][0..2], .big);
            idx += 2;
        } else if (payload_len == 127) {
            payload_len = std.mem.readInt(u64, self.header_buf[idx..][0..8], .big);
            idx += 8;
        }

        if (opcode.isControl() and payload_len > 125) return Error.ControlTooLarge;
        if (payload_len > self.max_payload_len) return Error.MessageTooLarge;

        switch (self.role) {
            .server => if (!masked) return Error.MissingMask,
            .client => if (masked) return Error.UnexpectedMask,
        }

        var mask_key: ?[4]u8 = null;
        if (masked) {
            var key: [4]u8 = undefined;
            @memcpy(&key, self.header_buf[idx .. idx + 4]);
            mask_key = key;
            self.current_mask = Mask.init(mask_key.?);
        } else {
            self.current_mask = null;
        }

        self.pending_header = .{
            .fin = (b0 & 0x80) != 0,
            .rsv1 = (b0 & 0x40) != 0,
            .rsv2 = (b0 & 0x20) != 0,
            .rsv3 = (b0 & 0x10) != 0,
            .opcode = opcode,
            .masked = masked,
            .payload_len = payload_len,
            .mask_key = mask_key,
        };
        self.payload_remaining = @intCast(payload_len);
        return true;
    }

    fn resetHeaderState(self: *Parser) void {
        self.state = .header;
        self.pending_header = .{};
        self.payload_remaining = 0;
        self.current_mask = null;
        self.frame_end_pending = false;
        self.header_len = 0;
        self.need_bytes = 2;
    }
};

pub const FrameHandler = struct {
    parser: Parser,
    allocator: std.mem.Allocator,
    fragmented_type: ?MessageType = null,
    message: std.ArrayListUnmanaged(u8) = .{},

    pub const Event = union(enum) {
        data: []const u8,
        data_end: struct {
            opcode: MessageType,
            data: []const u8,
        },
        ping: []const u8,
        pong: []const u8,
        close: []const u8,
        need_more: void,
    };

    pub const Result = struct {
        consumed: usize,
        message: Event,
    };

    pub fn init(allocator: std.mem.Allocator, role: Role, options: Config) FrameHandler {
        return .{
            .parser = Parser.init(role, .{ .max_payload_len = options.max_payload_len }),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FrameHandler) void {
        self.message.deinit(self.allocator);
    }

    pub fn feed(self: *FrameHandler, bytes: []u8) !Result {
        const result = try self.parser.feed(bytes);
        switch (result.event) {
            .need_more => return .{ .consumed = result.consumed, .message = .need_more },
            .frame_header => |hdr| {
                _ = hdr;
                return .{ .consumed = result.consumed, .message = .need_more };
            },
            .frame_end => {
                if (self.fragmented_type) |msg_type| {
                    const data = try self.message.toOwnedSlice(self.allocator);
                    self.fragmented_type = null;
                    self.message = .{};
                    return .{
                        .consumed = result.consumed,
                        .message = .{ .data_end = .{ .opcode = msg_type, .data = data } },
                    };
                }
                return .{ .consumed = result.consumed, .message = .need_more };
            },
            .payload => |payload| {
                const hdr = self.parser.pending_header;
                switch (hdr.opcode) {
                    .ping => return .{ .consumed = result.consumed, .message = .{ .ping = payload } },
                    .pong => return .{ .consumed = result.consumed, .message = .{ .pong = payload } },
                    .close => return .{ .consumed = result.consumed, .message = .{ .close = payload } },
                    .text, .binary => {
                        const msg_type: MessageType = if (hdr.opcode == .text) .text else .binary;
                        if (hdr.fin) {
                            return .{
                                .consumed = result.consumed,
                                .message = .{ .data_end = .{ .opcode = msg_type, .data = payload } },
                            };
                        }
                        self.fragmented_type = msg_type;
                        try self.message.appendSlice(self.allocator, payload);
                        return .{ .consumed = result.consumed, .message = .{ .data = payload } };
                    },
                    .continuation => {
                        if (self.fragmented_type == null) return Error.UnexpectedContinuation;
                        try self.message.appendSlice(self.allocator, payload);
                        return .{ .consumed = result.consumed, .message = .{ .data = payload } };
                    },
                    else => return Error.InvalidOpcode,
                }
            },
        }
    }
};

pub const Message = union(enum) {
    text: []u8,
    binary: []u8,
    close: CloseMessage,
};

pub const CloseMessage = struct {
    code: ?CloseCode,
    reason: []u8,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    role: Role,
    handler: FrameHandler,
    closed: bool = false,

    pub fn init(allocator: std.mem.Allocator, role: Role, options: Config) Session {
        return .{
            .allocator = allocator,
            .role = role,
            .handler = FrameHandler.init(allocator, role, .{ .max_payload_len = options.max_payload_len }),
        };
    }

    pub fn deinit(self: *Session) void {
        self.handler.deinit();
    }

    pub fn sendText(self: *Session, handle: std.net.Stream.Handle, text: []const u8) !void {
        try self.sendTextWriter(self.role, handle, text);
    }

    pub fn sendBinary(self: *Session, handle: std.net.Stream.Handle, bytes: []const u8) !void {
        try self.sendBinaryWriter(self.role, handle, bytes);
    }

    pub fn ping(self: *Session, handle: std.net.Stream.Handle, bytes: []const u8) !void {
        try self.pingWriter(handle, bytes);
    }

    pub fn close(self: *Session, handle: std.net.Stream.Handle, code: CloseCode, reason: []const u8) !void {
        try self.closeWriter(handle, code, reason);
    }

    pub fn sendTextWriter(self: *Session, role: Role, writer: anytype, text: []const u8) !void {
        _ = self;
        try writeFramed(writer, text, .{ .opcode = .text, .masked = role == .client });
    }

    pub fn sendBinaryWriter(self: *Session, role: Role, writer: anytype, bytes: []const u8) !void {
        _ = self;
        try writeFramed(writer, bytes, .{ .opcode = .binary, .masked = role == .client });
    }

    pub fn pingWriter(self: *Session, writer: anytype, bytes: []const u8) !void {
        try writeFramed(writer, bytes, .{ .opcode = .ping, .masked = self.role == .client });
    }

    pub fn closeWriter(self: *Session, writer: anytype, code: CloseCode, reason: []const u8) !void {
        self.closed = true;
        try writeCloseAny(writer, code, reason, self.role == .client);
    }

    pub fn receive(self: *Session, handle: std.net.Stream.Handle, scratch: []u8) !Message {
        return try self.receiveIO(handle, handle, scratch);
    }

    pub fn receiveReader(self: *Session, reader: anytype, writer: anytype, scratch: []u8) !Message {
        return try self.receiveIO(reader, writer, scratch);
    }

    pub fn receiveIO(self: *Session, reader: anytype, writer: anytype, scratch: []u8) !Message {
        while (true) {
            const read_count = try readSome(reader, scratch);
            if (read_count == 0) return error.EndOfStream;
            var window = scratch[0..read_count];
            while (window.len > 0) {
                const result = try self.handler.feed(window);
                window = window[result.consumed..];
                switch (result.message) {
                    .need_more, .data => {},
                    .ping => |payload| {
                        try writeFramed(writer, payload, .{
                            .opcode = .pong,
                            .masked = self.role == .client,
                        });
                    },
                    .pong => {},
                    .close => |payload| {
                        self.closed = true;
                        const close_msg = try parseClosePayload(self.allocator, payload);
                        return .{ .close = close_msg };
                    },
                    .data_end => |end| {
                        const owned = try self.allocator.dupe(u8, end.data);
                        return switch (end.opcode) {
                            .text => .{ .text = owned },
                            .binary => .{ .binary = owned },
                        };
                    },
                }
            }
        }
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    session: Session,
    protocol: ?[]u8 = null,

    pub fn connect(allocator: std.mem.Allocator, random: std.Random, url_text: []const u8, options: struct {
        protocol: ?[]const u8 = null,
        origin: ?[]const u8 = null,
        extra_headers: []const UpgradeRequest.Header = &.{},
        max_payload_len: u64 = 16 * 1024 * 1024,
    }) !Client {
        const url = try Url.parse(url_text);
        if (url.secure) return Error.UnsupportedSecureWebSocket;

        const host = if (url.port) |port|
            try std.fmt.allocPrint(allocator, "{s}:{d}", .{ url.host, port })
        else
            try allocator.dupe(u8, url.host);
        defer allocator.free(host);

        const target = try url.targetAlloc(allocator);
        defer allocator.free(target);

        var key: ClientKey = undefined;
        makeClientKey(random, &key);

        const stream = try std.net.tcpConnectToHost(allocator, url.host, url.portOrDefault());
        errdefer stream.close();
        return try Client.adoptConnectedStream(allocator, random, stream, url, .{
            .protocol = options.protocol,
            .origin = options.origin,
            .extra_headers = options.extra_headers,
            .max_payload_len = options.max_payload_len,
        });
    }

    pub fn adoptConnectedStream(
        allocator: std.mem.Allocator,
        random: std.Random,
        stream: std.net.Stream,
        url: Url,
        options: struct {
            protocol: ?[]const u8 = null,
            origin: ?[]const u8 = null,
            extra_headers: []const UpgradeRequest.Header = &.{},
            max_payload_len: u64 = 16 * 1024 * 1024,
        },
    ) !Client {
        const host = if (url.port) |port|
            try std.fmt.allocPrint(allocator, "{s}:{d}", .{ url.host, port })
        else
            try allocator.dupe(u8, url.host);
        defer allocator.free(host);

        const target = try url.targetAlloc(allocator);
        defer allocator.free(target);

        var key: ClientKey = undefined;
        makeClientKey(random, &key);

        try writeClientUpgrade(stream.handle, .{
            .host = host,
            .target = target,
            .key = &key,
            .protocol = options.protocol,
            .origin = options.origin,
            .extra_headers = options.extra_headers,
        });

        const info = try readAndVerifyUpgrade(stream.handle, &key);
        var session = Session.init(allocator, .client, .{ .max_payload_len = options.max_payload_len });
        errdefer session.deinit();

        return .{
            .allocator = allocator,
            .stream = stream,
            .session = session,
            .protocol = if (info.protocol) |value| try allocator.dupe(u8, value) else null,
        };
    }

    pub fn deinit(self: *Client) void {
        if (self.protocol) |protocol| self.allocator.free(protocol);
        self.session.deinit();
        self.stream.close();
    }

    pub fn sendText(self: *Client, text: []const u8) !void {
        try self.session.sendText(self.stream.handle, text);
    }

    pub fn sendBinary(self: *Client, bytes: []const u8) !void {
        try self.session.sendBinary(self.stream.handle, bytes);
    }

    pub fn ping(self: *Client, bytes: []const u8) !void {
        try self.session.ping(self.stream.handle, bytes);
    }

    pub fn close(self: *Client, code: CloseCode, reason: []const u8) !void {
        try self.session.close(self.stream.handle, code, reason);
    }

    pub fn receive(self: *Client, scratch: []u8) !Message {
        return try self.session.receive(self.stream.handle, scratch);
    }
};

pub const SecureClient = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    session: Session,
    protocol: ?[]u8 = null,
    ca_bundle: std.crypto.Certificate.Bundle = .{},
    stream_writer: std.net.Stream.Writer,
    stream_reader: std.net.Stream.Reader,
    tls_client: std.crypto.tls.Client,
    tls_read_buffer: []u8,
    tls_write_buffer: []u8,
    socket_write_buffer: []u8,
    socket_read_buffer: []u8,

    pub fn connect(allocator: std.mem.Allocator, random: std.Random, url_text: []const u8, options: struct {
        protocol: ?[]const u8 = null,
        origin: ?[]const u8 = null,
        extra_headers: []const UpgradeRequest.Header = &.{},
        max_payload_len: u64 = 16 * 1024 * 1024,
    }) !SecureClient {
        const url = try Url.parse(url_text);
        if (!url.secure) return Error.InvalidWebSocketUrl;

        const stream = try std.net.tcpConnectToHost(allocator, url.host, url.portOrDefault());
        errdefer stream.close();

        var ca_bundle: std.crypto.Certificate.Bundle = .{};
        errdefer ca_bundle.deinit(allocator);
        try ca_bundle.rescan(allocator);

        const min = std.crypto.tls.Client.min_buffer_len;
        const tls_read_buffer = try allocator.alloc(u8, min + 8192);
        errdefer allocator.free(tls_read_buffer);
        const tls_write_buffer = try allocator.alloc(u8, min);
        errdefer allocator.free(tls_write_buffer);
        const socket_write_buffer = try allocator.alloc(u8, min);
        errdefer allocator.free(socket_write_buffer);
        const socket_read_buffer = try allocator.alloc(u8, min);
        errdefer allocator.free(socket_read_buffer);

        var stream_writer = stream.writer(tls_write_buffer);
        var stream_reader = stream.reader(socket_read_buffer);
        var tls_client = try std.crypto.tls.Client.init(
            stream_reader.interface(),
            &stream_writer.interface,
            .{
                .host = .{ .explicit = url.host },
                .ca = .{ .bundle = ca_bundle },
                .read_buffer = tls_read_buffer,
                .write_buffer = socket_write_buffer,
                .allow_truncation_attacks = true,
            },
        );

        const host = if (url.port) |port|
            try std.fmt.allocPrint(allocator, "{s}:{d}", .{ url.host, port })
        else
            try allocator.dupe(u8, url.host);
        defer allocator.free(host);

        const target = try url.targetAlloc(allocator);
        defer allocator.free(target);

        var key: ClientKey = undefined;
        makeClientKey(random, &key);

        try writeClientUpgradeWriter(tls_client.writer, .{
            .host = host,
            .target = target,
            .key = &key,
            .protocol = options.protocol,
            .origin = options.origin,
            .extra_headers = options.extra_headers,
        });

        const info = try readAndVerifyUpgradeReader(&tls_client.reader, &key);
        var session = Session.init(allocator, .client, .{ .max_payload_len = options.max_payload_len });
        errdefer session.deinit();

        return .{
            .allocator = allocator,
            .stream = stream,
            .session = session,
            .protocol = if (info.protocol) |value| try allocator.dupe(u8, value) else null,
            .ca_bundle = ca_bundle,
            .stream_writer = stream_writer,
            .stream_reader = stream_reader,
            .tls_client = tls_client,
            .tls_read_buffer = tls_read_buffer,
            .tls_write_buffer = tls_write_buffer,
            .socket_write_buffer = socket_write_buffer,
            .socket_read_buffer = socket_read_buffer,
        };
    }

    pub fn deinit(self: *SecureClient) void {
        if (self.protocol) |protocol| self.allocator.free(protocol);
        self.session.deinit();
        self.stream.close();
        self.ca_bundle.deinit(self.allocator);
        self.allocator.free(self.tls_read_buffer);
        self.allocator.free(self.tls_write_buffer);
        self.allocator.free(self.socket_write_buffer);
        self.allocator.free(self.socket_read_buffer);
    }

    pub fn sendText(self: *SecureClient, text: []const u8) !void {
        try self.session.sendTextWriter(.client, self.tls_client.writer, text);
    }

    pub fn sendBinary(self: *SecureClient, bytes: []const u8) !void {
        try self.session.sendBinaryWriter(.client, self.tls_client.writer, bytes);
    }

    pub fn ping(self: *SecureClient, bytes: []const u8) !void {
        try self.session.pingWriter(self.tls_client.writer, bytes);
    }

    pub fn close(self: *SecureClient, code: CloseCode, reason: []const u8) !void {
        try self.session.closeWriter(self.tls_client.writer, code, reason);
    }

    pub fn receive(self: *SecureClient, scratch: []u8) !Message {
        return try self.session.receiveReader(&self.tls_client.reader, self.tls_client.writer, scratch);
    }
};

pub const ServerConn = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    session: Session,
    handshake: HandshakeRequest,
    protocol: ?[]u8 = null,

    pub fn accept(allocator: std.mem.Allocator, stream: std.net.Stream, raw_request: []const u8, options: struct {
        protocol: ?[]const u8 = null,
        extra_headers: []const UpgradeResponse.Header = &.{},
        max_payload_len: u64 = 16 * 1024 * 1024,
    }) !ServerConn {
        const request = try HandshakeRequest.parse(raw_request);
        if (!std.mem.eql(u8, request.version, "13")) return Error.InvalidUpgradeRequest;
        if (options.protocol) |protocol| {
            if (!request.acceptsProtocol(protocol)) return Error.UpgradeRejected;
        }

        var response_bytes = std.ArrayList(u8).empty;
        defer response_bytes.deinit(allocator);
        try request.writeResponse(response_bytes.writer(allocator), options.protocol, options.extra_headers);
        try socket.sendAll(stream.handle, response_bytes.items);

        var session = Session.init(allocator, .server, .{ .max_payload_len = options.max_payload_len });
        errdefer session.deinit();

        return .{
            .allocator = allocator,
            .stream = stream,
            .session = session,
            .handshake = request,
            .protocol = if (options.protocol) |value| try allocator.dupe(u8, value) else null,
        };
    }

    pub fn readAndAccept(allocator: std.mem.Allocator, stream: std.net.Stream, buffer: []u8, options: struct {
        protocol: ?[]const u8 = null,
        extra_headers: []const UpgradeResponse.Header = &.{},
        max_payload_len: u64 = 16 * 1024 * 1024,
    }) !ServerConn {
        const read_result = try readHandshakeRequest(stream.handle, buffer);
        _ = read_result.raw_len;
        return try ServerConn.accept(allocator, stream, buffer[0..read_result.raw_len], .{
            .protocol = options.protocol,
            .extra_headers = options.extra_headers,
            .max_payload_len = options.max_payload_len,
        });
    }

    pub fn acceptHttpRequest(allocator: std.mem.Allocator, stream: std.net.Stream, request: http_server.Request, options: struct {
        protocol: ?[]const u8 = null,
        extra_headers: []const UpgradeResponse.Header = &.{},
        max_payload_len: u64 = 16 * 1024 * 1024,
    }) !ServerConn {
        return try ServerConn.accept(allocator, stream, request.raw, options);
    }

    pub fn deinit(self: *ServerConn) void {
        if (self.protocol) |protocol| self.allocator.free(protocol);
        self.session.deinit();
        self.stream.close();
    }

    pub fn sendText(self: *ServerConn, text: []const u8) !void {
        try self.session.sendText(self.stream.handle, text);
    }

    pub fn sendBinary(self: *ServerConn, bytes: []const u8) !void {
        try self.session.sendBinary(self.stream.handle, bytes);
    }

    pub fn ping(self: *ServerConn, bytes: []const u8) !void {
        try self.session.ping(self.stream.handle, bytes);
    }

    pub fn close(self: *ServerConn, code: CloseCode, reason: []const u8) !void {
        try self.session.close(self.stream.handle, code, reason);
    }

    pub fn receive(self: *ServerConn, scratch: []u8) !Message {
        return try self.session.receive(self.stream.handle, scratch);
    }
};

fn isKnownOpcode(opcode: Opcode) bool {
    return switch (opcode) {
        .continuation, .text, .binary, .close, .ping, .pong => true,
        else => false,
    };
}

fn containsTokenIgnoreCase(value: []const u8, token: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |part| {
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, part, " \t"), token)) return true;
    }
    return false;
}

fn writeClientUpgrade(handle: std.net.Stream.Handle, request: UpgradeRequest) !void {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.heap.page_allocator);
    try request.write(bytes.writer(std.heap.page_allocator));
    try socket.sendAll(handle, bytes.items);
}

fn readAndVerifyUpgrade(handle: std.net.Stream.Handle, expected_key: []const u8) !UpgradeInfo {
    return try readAndVerifyUpgradeReader(handle, expected_key);
}

fn writeClientUpgradeWriter(writer: anytype, request: UpgradeRequest) !void {
    try request.write(writer);
}

fn readAndVerifyUpgradeReader(reader: anytype, expected_key: []const u8) !UpgradeInfo {
    var response_buf: [8192]u8 = undefined;
    var used: usize = 0;
    while (std.mem.indexOf(u8, response_buf[0..used], "\r\n\r\n") == null) {
        if (used == response_buf.len) return Error.HeaderTooLarge;
        const amt = try readSome(reader, response_buf[used..]);
        if (amt == 0) return error.EndOfStream;
        used += amt;
    }
    return try verifyUpgradeResponse(response_buf[0..used], expected_key);
}

fn writeFramed(writer: anytype, payload: []const u8, options: FrameOptions) !void {
    var frame_options = options;
    if (frame_options.masked and frame_options.mask_key == null) {
        var key: [4]u8 = undefined;
        std.crypto.random.bytes(&key);
        frame_options.mask_key = key;
    }
    const WriterType = @TypeOf(writer);
    if (WriterType == std.net.Stream.Handle) {
        var bytes = std.ArrayList(u8).empty;
        defer bytes.deinit(std.heap.page_allocator);
        try writeFrame(bytes.writer(std.heap.page_allocator), payload, frame_options);
        try socket.sendAll(writer, bytes.items);
        return;
    }
    try writeFrame(writer, payload, frame_options);
}

fn writeCloseAny(writer: anytype, code: CloseCode, reason: []const u8, masked: bool) !void {
    const WriterType = @TypeOf(writer);
    if (WriterType == std.net.Stream.Handle) {
        var bytes = std.ArrayList(u8).empty;
        defer bytes.deinit(std.heap.page_allocator);
        try writeClose(bytes.writer(std.heap.page_allocator), code, reason, masked);
        try socket.sendAll(writer, bytes.items);
        return;
    }
    try writeClose(writer, code, reason, masked);
}

fn readSome(reader: anytype, buffer: []u8) !usize {
    const ReaderType = @TypeOf(reader);
    if (ReaderType == std.net.Stream.Handle) {
        return try socket.recv(reader, buffer);
    }
    return try reader.readSliceShort(buffer);
}

fn parseClosePayload(allocator: std.mem.Allocator, payload: []const u8) !CloseMessage {
    if (payload.len == 0) {
        return .{ .code = null, .reason = try allocator.dupe(u8, "") };
    }
    if (payload.len == 1) return Error.InvalidClosePayload;
    const code_int = std.mem.readInt(u16, payload[0..2], .big);
    const reason = try allocator.dupe(u8, payload[2..]);
    return .{
        .code = @enumFromInt(code_int),
        .reason = reason,
    };
}

fn sendRawFrame(handle: std.net.Stream.Handle, payload: []const u8, options: FrameOptions) !void {
    var list = std.ArrayList(u8).empty;
    defer list.deinit(std.heap.page_allocator);

    var frame_options = options;
    if (frame_options.masked and frame_options.mask_key == null) {
        var key: [4]u8 = undefined;
        std.crypto.random.bytes(&key);
        frame_options.mask_key = key;
    }

    try writeFrame(list.writer(std.heap.page_allocator), payload, frame_options);
    try socket.sendAll(handle, list.items);
}

test "websocket url parses host path query and port" {
    const url = try Url.parse("wss://example.com:444/socket/chat?q=1");
    try std.testing.expect(url.secure);
    try std.testing.expectEqualStrings("example.com", url.host);
    try std.testing.expectEqual(@as(u16, 444), url.port.?);
    try std.testing.expectEqualStrings("/socket/chat", url.path);
    try std.testing.expectEqualStrings("q=1", url.query);
}

test "computeAcceptKey matches RFC sample" {
    var out: AcceptKey = undefined;
    const accept = computeAcceptKey("dGhlIHNhbXBsZSBub25jZQ==", &out);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept);
}

test "mask applies across chunks" {
    var mask = Mask.init(.{ 0x12, 0x34, 0x56, 0x78 });
    var part1 = [_]u8{ 'H', 'e' };
    var part2 = [_]u8{ 'l', 'l', 'o' };
    mask.apply(&part1);
    mask.apply(&part2);

    var unmask = Mask.init(.{ 0x12, 0x34, 0x56, 0x78 });
    unmask.apply(&part1);
    unmask.apply(&part2);
    try std.testing.expectEqualStrings("He", &part1);
    try std.testing.expectEqualStrings("llo", &part2);
}

test "writeFrame writes unmasked server frame" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try writeFrame(stream.writer(), "Hi", .{ .opcode = .text });
    const out = stream.getWritten();
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0x02, 'H', 'i' }, out);
}

test "parser yields header payload end for masked client frame" {
    var parser = Parser.init(.server, .{});
    var bytes = [_]u8{
        0x81,
        0x82,
        0x12, 0x34, 0x56, 0x78,
        0x5A, 0x5D,
    };

    const r1 = try parser.feed(bytes[0..2]);
    try std.testing.expectEqual(@as(usize, 2), r1.consumed);
    try std.testing.expect(r1.event == .need_more);

    const r2 = try parser.feed(bytes[2..6]);
    try std.testing.expectEqual(@as(usize, 4), r2.consumed);
    try std.testing.expect(r2.event == .frame_header);
    try std.testing.expectEqual(@as(u64, 2), r2.event.frame_header.payload_len);

    const r3 = try parser.feed(bytes[6..]);
    try std.testing.expectEqual(@as(usize, 2), r3.consumed);
    try std.testing.expect(r3.event == .payload);
    try std.testing.expectEqualStrings("Hi", r3.event.payload);

    const r4 = try parser.feed(&.{});
    try std.testing.expectEqual(@as(usize, 0), r4.consumed);
    try std.testing.expect(r4.event == .frame_end);
}

test "parser rejects unmasked client frame for server role" {
    var parser = Parser.init(.server, .{});
    var bytes = [_]u8{ 0x81, 0x01, 'A' };
    try std.testing.expectError(Error.MissingMask, parser.feed(bytes[0..2]));
}

test "upgrade response writes accept header" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try (UpgradeResponse{ .key = "dGhlIHNhbXBsZSBub25jZQ==" }).write(stream.writer());
    const out = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "101 Switching Protocols") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=") != null);
}

test "upgrade request writes client handshake" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try (UpgradeRequest{
        .host = "example.com",
        .target = "/chat?x=1",
        .key = "dGhlIHNhbXBsZSBub25jZQ==",
        .protocol = "chat",
    }).write(stream.writer());
    const out = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "GET /chat?x=1 HTTP/1.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Sec-WebSocket-Protocol: chat") != null);
}

test "verify upgrade response checks required headers" {
    const response =
        "HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: keep-alive, Upgrade\r\n" ++
        "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n" ++
        "Sec-WebSocket-Protocol: chat\r\n\r\n";
    const info = try verifyUpgradeResponse(response, "dGhlIHNhbXBsZSBub25jZQ==");
    try std.testing.expectEqual(@as(u16, 101), info.status_code);
    try std.testing.expectEqualStrings("chat", info.protocol.?);
}

test "url target alloc includes query" {
    const allocator = std.testing.allocator;
    const url = try Url.parse("ws://example.com/chat?room=1");
    const target = try url.targetAlloc(allocator);
    defer allocator.free(target);
    try std.testing.expectEqualStrings("/chat?room=1", target);
}

test "handshake request parses upgrade fields" {
    const raw =
        "GET /chat?room=1 HTTP/1.1\r\n" ++
        "Host: example.com\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: keep-alive, Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "Sec-WebSocket-Protocol: chat, superchat\r\n\r\n";
    const req = try HandshakeRequest.parse(raw);
    try std.testing.expectEqualStrings("GET", req.method);
    try std.testing.expectEqualStrings("/chat?room=1", req.target);
    try std.testing.expectEqualStrings("example.com", req.host);
    try std.testing.expectEqualStrings("13", req.version);
    try std.testing.expect(req.acceptsProtocol("chat"));
    try std.testing.expect(req.acceptsProtocol("superchat"));
    try std.testing.expect(!req.acceptsProtocol("other"));
}

test "handshake request writes upgrade response" {
    const raw =
        "GET /ws HTTP/1.1\r\n" ++
        "Host: localhost:9000\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n\r\n";
    const req = try HandshakeRequest.parse(raw);
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try req.writeResponse(stream.writer(), null, &.{});
    const out = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "101 Switching Protocols") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=") != null);
}

test "handshake request protocols splits offered values" {
    const allocator = std.testing.allocator;
    const raw =
        "GET /ws HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: keykeykeykeykeykeykeyk=\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "Sec-WebSocket-Protocol: a, b , c\r\n\r\n";
    const req = try HandshakeRequest.parse(raw);
    const protocols = try req.protocols(allocator);
    defer allocator.free(protocols);
    try std.testing.expectEqual(@as(usize, 3), protocols.len);
    try std.testing.expectEqualStrings("a", protocols[0]);
    try std.testing.expectEqualStrings("b", protocols[1]);
    try std.testing.expectEqualStrings("c", protocols[2]);
}

test "read handshake request parses from socket buffer" {
    var server = try std.net.Address.listen(try std.net.Address.parseIp("127.0.0.1", 0), .{});
    defer server.deinit();

    const port = server.listen_address.in.getPort();
    const client = try std.net.tcpConnectToHost(std.testing.allocator, "127.0.0.1", port);
    defer client.close();
    const accepted = try server.accept();
    defer accepted.stream.close();

    const raw =
        "GET /ws HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n\r\n";
    try socket.sendAll(client.handle, raw);

    var buffer: [1024]u8 = undefined;
    const result = try readHandshakeRequest(accepted.stream.handle, &buffer);
    try std.testing.expectEqualStrings("/ws", result.request.target);
    try std.testing.expect(result.raw_len > 0);
}

test "http server request can be parsed as websocket handshake" {
    const raw =
        "GET /socket HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: keykeykeykeykeykeykeyk=\r\n" ++
        "Sec-WebSocket-Version: 13\r\n\r\n";
    const request = http_server.Request{
        .method = "GET",
        .target = "/socket",
        .version = "HTTP/1.1",
        .headers = &.{
            .{ .name = "Host", .value = "localhost" },
            .{ .name = "Upgrade", .value = "websocket" },
            .{ .name = "Connection", .value = "Upgrade" },
            .{ .name = "Sec-WebSocket-Key", .value = "keykeykeykeykeykeykeyk=" },
            .{ .name = "Sec-WebSocket-Version", .value = "13" },
        },
        .body = "",
        .raw = raw,
    };
    const handshake = try HandshakeRequest.parse(request.raw);
    try std.testing.expectEqualStrings("localhost", handshake.host);
    try std.testing.expectEqualStrings("/socket", handshake.target);
}

test "client and server websocket echo roundtrip" {
    const allocator = std.testing.allocator;

    const TestServer = struct {
        port: u16,

        fn run(self: @This()) !void {
            var listener = try std.net.Address.listen(try std.net.Address.parseIp("127.0.0.1", self.port), .{});
            defer listener.deinit();

            const accepted = try listener.accept();

            var handshake_buf: [4096]u8 = undefined;
            var conn = try ServerConn.readAndAccept(allocator, accepted.stream, &handshake_buf, .{});
            defer conn.deinit();

            var scratch: [4096]u8 = undefined;
            const msg = try conn.receive(&scratch);
            switch (msg) {
                .text => |text| {
                    defer allocator.free(text);
                    try conn.sendText(text);
                    try conn.close(.normal, "bye");
                },
                .binary => |bytes| {
                    defer allocator.free(bytes);
                    return error.UnexpectedBinary;
                },
                .close => |close_msg| {
                    defer allocator.free(close_msg.reason);
                    return error.UnexpectedClose;
                },
            }
        }
    };

    const port: u16 = 9236;
    const thread = try std.Thread.spawn(.{}, TestServer.run, .{TestServer{ .port = port }});
    defer thread.join();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var prng = std.Random.DefaultPrng.init(0x1234_5678);
    var client = try Client.connect(allocator, prng.random(), "ws://127.0.0.1:9236/ws", .{});
    defer client.deinit();

    try client.sendText("echo me");
    var scratch: [4096]u8 = undefined;
    const reply = try client.receive(&scratch);
    switch (reply) {
        .text => |text| {
            defer allocator.free(text);
            try std.testing.expectEqualStrings("echo me", text);
        },
        .binary => |bytes| {
            defer allocator.free(bytes);
            return error.UnexpectedBinary;
        },
        .close => |close_msg| {
            defer allocator.free(close_msg.reason);
            return error.UnexpectedClose;
        },
    }
}
