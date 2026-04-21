const std = @import("std");
const fmus = @import("fmus");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var loaded = try fmus.supabase.config.loadFromEnvFileOrProcess(allocator, "..\\.env", .service);
    defer loaded.deinit();

    const plan = fmus.supabase.keepalive.Plan.freeTierDaily();
    var report = try fmus.supabase.keepalive.run(allocator, loaded.config, plan);
    defer report.deinit();

    std.debug.print("Supabase keepalive for {s}\n", .{report.project_url});
    std.debug.print("Cron: {s}\n", .{plan.cron_expr});
    for (report.results) |result| {
        std.debug.print("- {s}: ok={any} status={any}\n", .{
            result.label,
            result.ok,
            result.status_code,
        });
        if (result.detail) |detail| {
            std.debug.print("  detail: {s}\n", .{detail});
        }
    }
}
