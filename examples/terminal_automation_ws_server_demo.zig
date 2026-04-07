const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var host = fmus.terminal.Automation.AutomationHost.init(allocator, .{
        .event_log_path = "C:\\github-sido\\kerjaan\\claude-code-repos\\fmus-zig\\_legacy\\automation-events.jsonl",
    });
    defer host.deinit();

    var server = fmus.terminal.AutomationWs.AutomationWsServer.init(allocator, &host, .{
        .address = "127.0.0.1",
        .port = 9311,
        .protocol = "fmus.automation.v1",
    });
    defer server.deinit();

    std.debug.print(
        "fmus terminal automation ws server listening on ws://127.0.0.1:9311\nmethods: create_shell_session, send_text, get_visible_text, poll_events, save_screenshot_png\n",
        .{},
    );

    try server.listen();
}
