const std = @import("std");
const root = @import("root");
const http = if (@hasDecl(root, "http")) root.http else @import("../http.zig");
const json = if (@hasDecl(root, "json")) root.json else @import("../json.zig");
const config_mod = @import("config.zig");
const errors = @import("errors.zig");
const session_mod = @import("session.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    config: config_mod.Config,

    pub fn init(allocator: std.mem.Allocator, config: config_mod.Config) Client {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn signUp(self: Client, email: []const u8, password: []const u8) !session_mod.Session {
        return try self.sessionRequest("signup", .{
            .email = email,
            .password = password,
        });
    }

    pub fn signInWithPassword(self: Client, email: []const u8, password: []const u8) !session_mod.Session {
        const auth_url = try self.config.authUrlAlloc(self.allocator);
        defer self.allocator.free(auth_url);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/token?grant_type=password", .{auth_url});
        defer self.allocator.free(url);

        return try self.sessionRequestUrl(url, .{
            .email = email,
            .password = password,
        });
    }

    pub fn refresh(self: Client, refresh_token: []const u8) !session_mod.Session {
        const auth_url = try self.config.authUrlAlloc(self.allocator);
        defer self.allocator.free(auth_url);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/token?grant_type=refresh_token", .{auth_url});
        defer self.allocator.free(url);

        return try self.sessionRequestUrl(url, .{
            .refresh_token = refresh_token,
        });
    }

    pub fn signOut(self: Client, access_token: []const u8) !void {
        const auth_url = try self.config.authUrlAlloc(self.allocator);
        defer self.allocator.free(auth_url);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/logout", .{auth_url});
        defer self.allocator.free(url);

        var headers = try self.baseHeaders(true, access_token);
        defer headers.deinit();

        var response = try http.post(url).header(headers.slice()).send(self.allocator);
        defer response.deinit();
        if (!response.ok()) return errors.Error.AuthFailed;
    }

    pub fn getUser(self: Client, access_token: []const u8) !session_mod.User {
        const UserResponse = struct {
            user: session_mod.User,
        };

        const auth_url = try self.config.authUrlAlloc(self.allocator);
        defer self.allocator.free(auth_url);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/user", .{auth_url});
        defer self.allocator.free(url);

        var headers = try self.baseHeaders(true, access_token);
        defer headers.deinit();

        var response = try http.get(url).header(headers.slice()).send(self.allocator);
        defer response.deinit();
        if (!response.ok()) return errors.Error.AuthFailed;

        const parsed = try response.jsonParse(UserResponse);
        return parsed.user;
    }

    pub fn settings(self: Client) !http.Response {
        const auth_url = try self.config.authUrlAlloc(self.allocator);
        defer self.allocator.free(auth_url);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/settings", .{auth_url});
        defer self.allocator.free(url);

        var headers = try self.baseHeaders(false, null);
        defer headers.deinit();

        var response = try http.get(url).header(headers.slice()).send(self.allocator);
        if (!response.ok()) {
            response.deinit();
            return errors.Error.AuthFailed;
        }
        return response;
    }

    pub fn parseSessionJson(allocator: std.mem.Allocator, body: []const u8) !session_mod.Session {
        const SessionResponse = struct {
            access_token: []const u8,
            refresh_token: ?[]const u8 = null,
            token_type: ?[]const u8 = null,
            expires_in: ?i64 = null,
            user: ?session_mod.User = null,
        };

        const parsed = try json.parse(allocator, SessionResponse, body);
        return .{
            .access_token = parsed.access_token,
            .refresh_token = parsed.refresh_token,
            .token_type = parsed.token_type orelse "bearer",
            .expires_at_ms = if (parsed.expires_in) |expires_in| std.time.milliTimestamp() + (expires_in * std.time.ms_per_s) else null,
            .user = parsed.user,
        };
    }

    fn sessionRequest(self: Client, suffix: []const u8, payload: anytype) !session_mod.Session {
        const auth_url = try self.config.authUrlAlloc(self.allocator);
        defer self.allocator.free(auth_url);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ auth_url, suffix });
        defer self.allocator.free(url);

        return try self.sessionRequestUrl(url, payload);
    }

    fn sessionRequestUrl(self: Client, url: []const u8, payload: anytype) !session_mod.Session {
        const body = try json.stringifyAlloc(self.allocator, payload);
        defer self.allocator.free(body);

        var headers = try self.baseHeaders(false, null);
        defer headers.deinit();

        var response = try http.post(url).header(headers.slice()).body(body, "application/json").send(self.allocator);
        defer response.deinit();
        if (!response.ok()) return errors.Error.AuthFailed;
        return try parseSessionJson(self.allocator, response.body);
    }

    fn baseHeaders(self: Client, authenticated: bool, access_token: ?[]const u8) !http.OwnedHeaders {
        var headers = http.OwnedHeaders.init(self.allocator);
        errdefer headers.deinit();
        try headers.appendApiKey(self.config.api_key);
        try headers.append("accept", "application/json");
        try headers.append("accept-encoding", "identity");
        try headers.append("x-client-info", "fmus-zig/supabase");
        try headers.appendBearer(if (authenticated and access_token != null) access_token.? else self.config.api_key);
        return headers;
    }
};

test "auth parses session json" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parsed = try Client.parseSessionJson(arena,
        \\{"access_token":"at","refresh_token":"rt","token_type":"bearer","expires_in":3600,"user":{"id":"u1","email":"a@example.com","role":"authenticated"}}
    );
    try std.testing.expectEqualStrings("at", parsed.access_token);
    try std.testing.expectEqualStrings("rt", parsed.refresh_token.?);
    try std.testing.expectEqualStrings("u1", parsed.user.?.id);
}
