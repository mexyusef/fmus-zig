pub const types = @import("types.zig");
pub const router = @import("router.zig");
pub const stream = @import("stream.zig");
pub const ws_transport = @import("ws_transport.zig");

pub const Id = types.Id;
pub const ErrorObject = types.ErrorObject;
pub const RequestView = types.RequestView;
pub const NotificationView = types.NotificationView;
pub const ResponseView = types.ResponseView;
pub const MessageView = types.MessageView;
pub const RootView = types.RootView;
pub const Document = types.Document;
pub const ParseError = types.ParseError;
pub const StandardErrorCode = types.StandardErrorCode;

pub const Router = router.Router;
pub const DispatchError = router.DispatchError;

pub const StreamConfig = stream.StreamConfig;
pub const WsTransportServer = ws_transport.Server;
pub const WsTransportConfig = ws_transport.Config;

pub const parseMessageAlloc = types.parseMessageAlloc;
pub const requestAlloc = types.requestAlloc;
pub const notificationAlloc = types.notificationAlloc;
pub const resultAlloc = types.resultAlloc;
pub const resultJsonAlloc = types.resultJsonAlloc;
pub const errorAlloc = types.errorAlloc;
pub const errorJsonAlloc = types.errorJsonAlloc;
pub const ok = types.ok;

pub const readDelimitedFrameAlloc = stream.readDelimitedFrameAlloc;
pub const writeDelimitedFrame = stream.writeDelimitedFrame;
pub const readContentLengthFrameAlloc = stream.readContentLengthFrameAlloc;
pub const writeContentLengthFrame = stream.writeContentLengthFrame;

test {
    _ = @import("types.zig");
    _ = @import("router.zig");
    _ = @import("stream.zig");
    _ = @import("ws_transport.zig");
}
