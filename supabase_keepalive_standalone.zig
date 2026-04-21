const std = @import("std");
const fmus = @import("src/fmus.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var loaded = try fmus.supabase.config.loadFromEnvFileOrProcess(allocator, "..\\.env", .service);
    defer loaded.deinit();

    const plan = fmus.supabase.keepalive.Plan.freeTierDaily();
    var report = try fmus.supabase.keepalive.run(allocator, loaded.config, plan);
    defer report.deinit();

    std.debug.print("project={s}\n", .{report.project_url});
    std.debug.print("cron={s}\n", .{plan.cron_expr});
    std.debug.print("success={any}\n", .{report.succeeded()});
    for (report.results) |result| {
        std.debug.print("probe={s} ok={any} status={any}\n", .{
            result.label,
            result.ok,
            result.status_code,
        });
        if (result.detail) |detail| {
            const short = if (detail.len > 120) detail[0..120] else detail;
            std.debug.print("detail={s}\n", .{short});
        }
    }
}
