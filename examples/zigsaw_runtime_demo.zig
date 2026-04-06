const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var session_chat = fmus.prompt.Chat.init(allocator);
    defer session_chat.deinit();
    try session_chat.system("You are a routing assistant.");
    try session_chat.user("Send a digest to Discord and Slack.");

    const session_id = try fmus.id.prefixed(allocator, "sess");

    const persisted = try fmus.session.pruneCount(allocator, session_chat.items(), 8);

    var stream_buf = fmus.stream.Buffer.init(allocator);
    defer stream_buf.deinit();
    try stream_buf.push(.{ .kind = .progress, .name = "discord", .progress = 0.5 });
    try stream_buf.push(.{ .kind = .tool_call, .name = "send_message", .text = "{\"channel\":\"discord\"}" });

    const decision = fmus.policy.decide(.ask, &.{.{ .action = .channel_send, .mode = .allow }}, .channel_send);

    const tool_catalog = try fmus.tool.renderCatalog(allocator, &.{.{
        .name = "send_message",
        .description = "Send a message to a channel",
        .params = &.{
            .{ .name = "channel", .description = "Target channel" },
            .{ .name = "text", .description = "Message body" },
        },
    }});

    var trail = fmus.audit.Trail.init(allocator);
    defer trail.deinit();
    try trail.append(fmus.event.Event.init(.gateway_started, "zigsaw", "runtime booted"));
    const notice: fmus.notify.Notice = .{ .level = .info, .title = "route", .body = "discord relay ready" };
    try trail.append(notice.asEvent());
    const audit_text = try trail.render(allocator);

    const skill_doc = fmus.skill.Manifest{
        .name = "daily-digest",
        .version = "0.1.0",
        .description = "Send a daily digest",
        .permissions = &.{ "channel_send", "network" },
    };
    const plugin_doc = fmus.plugin.Manifest{
        .name = "discord-channel",
        .version = "0.1.0",
        .kind = "channel",
        .main = "discord.zig",
    };
    const package_id = try fmus.pkg.id(allocator, .{
        .name = "zigsaw-discord",
        .version = "0.1.0",
        .source = "git+https://example.invalid/zigsaw-discord",
    });

    const routed = fmus.command.route(&.{
        .{ .name = "doctor", .description = "Run diagnostics" },
        .{ .name = "gateway", .description = "Start gateway" },
    }, &.{ "doctor", "--verbose" }).?;

    const out = try fmus.json.prettyAlloc(allocator, .{
        .session_id = session_id,
        .persisted_messages = persisted.len,
        .stream_events = stream_buf.len(),
        .channel_send_allowed = decision.allowed,
        .tool_catalog = tool_catalog,
        .audit = audit_text,
        .skill = skill_doc.name,
        .plugin_kind = plugin_doc.kind,
        .package_id = package_id,
        .command = routed.def.name,
        .command_args = routed.args,
    });

    try std.fs.File.stdout().writeAll(out);
    try std.fs.File.stdout().writeAll("\n");
}
