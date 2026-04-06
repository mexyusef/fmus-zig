const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var work_q = fmus.queue.Queue(fmus.job.Job).init(allocator);
    defer work_q.deinit();

    const jid = try fmus.id.prefixed(allocator, "job");
    try work_q.push(fmus.job.Job.init(jid, "sync-discord"));

    var kv = fmus.kv.FileStore.init(allocator, "__zigsaw_demo_kv.json");
    defer kv.deinit();
    defer fmus.fs.remove("__zigsaw_demo_kv.json") catch {};
    try kv.set("gateway.mode", "loopback");
    try kv.save();

    const sender: fmus.contact.Contact = .{
        .id = .{ .channel = .discord, .value = "user-1" },
        .display_name = "Yusef",
    };

    var message = fmus.msg.Message.init("msg-1", .discord, sender);
    message.text = "hello from zigsaw";

    const cron = try fmus.cron.parse("0 9 * * *");
    const sse_evt = try fmus.sse.parseBlock(allocator,
        \\event: token
        \\data: hello
    );
    defer if (sse_evt.event) |v| allocator.free(v);
    defer allocator.free(sse_evt.data);

    const out = try fmus.json.prettyAlloc(allocator, .{
        .queued_jobs = work_q.len(),
        .next_job = work_q.peek().?.name,
        .channel = @tagName(message.channel),
        .message = message.text,
        .cron_match = cron.matches(.{ .minute = 0, .hour = 9, .day = 1, .month = 1, .weekday = 1 }),
        .sse_event = sse_evt.event,
        .store_value = kv.get("gateway.mode"),
    });

    try std.fs.File.stdout().writeAll(out);
    try std.fs.File.stdout().writeAll("\n");
}
