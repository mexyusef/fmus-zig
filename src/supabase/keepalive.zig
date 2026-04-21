const std = @import("std");
const time = @import("../time.zig");
const cron = @import("../cron.zig");
const config_mod = @import("config.zig");
const client_mod = @import("client.zig");

pub const ProbeKind = enum {
    auth_settings,
    storage_buckets,
};

pub const ProbeSpec = struct {
    kind: ProbeKind,
    label: []const u8,
};

pub const StepResult = struct {
    kind: ProbeKind,
    label: []const u8,
    ok: bool,
    status_code: ?u16 = null,
    detail: ?[]const u8 = null,
    started_ms: i64,
    ended_ms: i64,
};

pub const Report = struct {
    allocator: std.mem.Allocator,
    project_url: []const u8,
    results: []StepResult,

    pub fn deinit(self: *Report) void {
        self.allocator.free(self.project_url);
        for (self.results) |result| {
            if (result.detail) |value| self.allocator.free(value);
        }
        self.allocator.free(self.results);
    }

    pub fn succeeded(self: Report) bool {
        for (self.results) |result| {
            if (!result.ok) return false;
        }
        return true;
    }
};

pub const Plan = struct {
    probes: []const ProbeSpec,
    cron_expr: []const u8,

    pub fn freeTierDaily() Plan {
        return .{
            .probes = &.{
                .{ .kind = .auth_settings, .label = "auth-settings" },
                .{ .kind = .storage_buckets, .label = "storage-buckets" },
            },
            .cron_expr = "17 9 * * *",
        };
    }

    pub fn cronSchedule(self: Plan) !cron.Expr {
        return try cron.parse(self.cron_expr);
    }
};

pub fn run(allocator: std.mem.Allocator, config: config_mod.Config, plan: Plan) !Report {
    var results = std.ArrayList(StepResult).empty;
    errdefer {
        for (results.items) |result| {
            if (result.detail) |value| allocator.free(value);
        }
        results.deinit(allocator);
    }

    const client = client_mod.Client.init(allocator, config).withAccessToken(config.api_key);

    for (plan.probes) |probe| {
        const started_ms = time.nowMs();
        switch (probe.kind) {
            .auth_settings => {
                var response = client.auth.settings() catch |err| {
                    try results.append(allocator, .{
                        .kind = probe.kind,
                        .label = probe.label,
                        .ok = false,
                        .detail = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}),
                        .started_ms = started_ms,
                        .ended_ms = time.nowMs(),
                    });
                    continue;
                };
                defer response.deinit();
                try results.append(allocator, .{
                    .kind = probe.kind,
                    .label = probe.label,
                    .ok = response.ok(),
                    .status_code = response.statusCode(),
                    .detail = try summarizeBody(allocator, response.body),
                    .started_ms = started_ms,
                    .ended_ms = time.nowMs(),
                });
            },
            .storage_buckets => {
                var response = client.storage.listBuckets() catch |err| {
                    try results.append(allocator, .{
                        .kind = probe.kind,
                        .label = probe.label,
                        .ok = false,
                        .detail = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}),
                        .started_ms = started_ms,
                        .ended_ms = time.nowMs(),
                    });
                    continue;
                };
                defer response.deinit();
                try results.append(allocator, .{
                    .kind = probe.kind,
                    .label = probe.label,
                    .ok = response.ok(),
                    .status_code = response.statusCode(),
                    .detail = try summarizeBody(allocator, response.body),
                    .started_ms = started_ms,
                    .ended_ms = time.nowMs(),
                });
            },
        }
    }

    return .{
        .allocator = allocator,
        .project_url = try allocator.dupe(u8, config.url),
        .results = try results.toOwnedSlice(allocator),
    };
}

fn summarizeBody(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const limit: usize = 160;
    if (body.len <= limit) return try allocator.dupe(u8, body);
    return try std.fmt.allocPrint(allocator, "{s}...", .{body[0..limit]});
}

test "free tier plan has daily schedule and probes" {
    const plan = Plan.freeTierDaily();
    const expr = try plan.cronSchedule();
    try std.testing.expectEqual(@as(usize, 2), plan.probes.len);
    try std.testing.expect(expr.matches(.{ .minute = 17, .hour = 9, .day = 1, .month = 1, .weekday = 1 }));
}
