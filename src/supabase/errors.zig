const std = @import("std");

pub const Error = error{
    InvalidSupabaseUrl,
    UnexpectedStatus,
    AuthFailed,
    QueryFailed,
    StorageFailed,
    FunctionsFailed,
    RealtimeFailed,
    MissingSession,
};

pub const ApiError = struct {
    code: ?[]const u8 = null,
    message: []const u8,
    details: ?[]const u8 = null,
    hint: ?[]const u8 = null,
};

pub const Service = enum {
    auth,
    rest,
    storage,
    functions,
    realtime,
};

pub const Failure = struct {
    service: Service,
    status_code: u16,
    api_error: ?ApiError = null,
};

test "api error defaults" {
    const err: ApiError = .{ .message = "bad request" };
    try std.testing.expectEqualStrings("bad request", err.message);
    try std.testing.expect(err.code == null);
}
