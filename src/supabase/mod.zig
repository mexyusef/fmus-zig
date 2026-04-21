pub const config = @import("config.zig");
pub const Config = @import("config.zig").Config;
pub const Client = @import("client.zig").Client;
pub const auth = @import("auth.zig");
pub const errors = @import("errors.zig");
pub const functions = @import("functions.zig");
pub const keepalive = @import("keepalive.zig");
pub const phoenix = @import("phoenix.zig");
pub const query_builder = @import("query_builder.zig");
pub const realtime = @import("realtime.zig");
pub const rest = @import("rest.zig");
pub const session = @import("session.zig");
pub const session_store = @import("session_store.zig");
pub const storage = @import("storage.zig");

test {
    _ = @import("client.zig");
    _ = @import("auth.zig");
    _ = @import("config.zig");
    _ = @import("errors.zig");
    _ = @import("functions.zig");
    _ = @import("keepalive.zig");
    _ = @import("phoenix.zig");
    _ = @import("query_builder.zig");
    _ = @import("realtime.zig");
    _ = @import("rest.zig");
    _ = @import("session.zig");
    _ = @import("session_store.zig");
    _ = @import("storage.zig");
}
