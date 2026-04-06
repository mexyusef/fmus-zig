const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const plugin_entry = fmus.plugin_sdk.define(
        "discord",
        "Discord",
        "Discord channel plugin",
        &.{.{ .id = "channel.discord", .kind = .channel, .description = "Discord transport" }},
    );

    const validation = try fmus.plugin_contract.validate(allocator, .{
        .plugin_api_range = ">=2026.4.0",
        .built_with_host_version = "0.1.0",
    });
    defer allocator.free(validation.issues);

    var typing: fmus.typing.Controller = .{};
    typing.start();

    var runs: fmus.runstate.Machine = .{};
    runs.onStart();
    runs.onEnd();

    const route_key = try fmus.route.normalizeSessionKey(allocator, " Main ");
    const bind_id = try fmus.thread.bindingId(allocator, .{
        .channel = "discord",
        .conversation_id = "c1",
        .thread_id = "t1",
    });

    var pair = try fmus.pairing.create(allocator, "discord", "user-1");
    defer allocator.free(pair.code);
    fmus.pairing.approve(&pair);

    const provider_id = try fmus.provider.normalizeModelId(allocator, "Anthropic", "Claude-4");
    const replay_entries = try fmus.replay.sanitize(allocator, &.{
        fmus.prompt.Message.user("hello"),
        fmus.prompt.Message.assistant("hi"),
    }, .{});
    defer allocator.free(replay_entries);

    var gateway = fmus.gateway.Registry.init(allocator);
    defer gateway.deinit();
    try gateway.add(.{ .name = "browser.request", .description = "Browser request" });

    const webhook_ok = fmus.webhook.verify("secret", "secret");
    const rpc_ok = try fmus.rpc.ok(allocator, "1", .{ .ok = true });
    defer allocator.free(rpc_ok);

    const redacted = try fmus.sec.redactMiddle(allocator, "super-secret-token");
    defer allocator.free(redacted);

    const out = try fmus.json.prettyAlloc(allocator, .{
        .plugin = plugin_entry.id,
        .plugin_issues = validation.issues.len,
        .typing_active = typing.active,
        .busy = runs.status.busy,
        .route_key = route_key,
        .thread_binding = bind_id,
        .paired = pair.approved,
        .provider = provider_id,
        .replay_count = replay_entries.len,
        .gateway_has_method = gateway.has("browser.request"),
        .webhook_ok = webhook_ok,
        .rpc = rpc_ok,
        .allowlisted = fmus.allowlist.matches(&.{ "discord:*" }, "discord:user-1"),
        .group_policy = fmus.group.allows(.mentions_only, true, false),
        .redacted = redacted,
        .safeeq = fmus.safeeq.bytes("abc", "abc"),
    });

    try std.fs.File.stdout().writeAll(out);
    try std.fs.File.stdout().writeAll("\n");
}
