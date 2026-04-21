const std = @import("std");
const root = @import("root");
const http = if (@hasDecl(root, "http")) root.http else @import("../http.zig");
const errors = @import("errors.zig");

pub const Count = enum {
    exact,
    planned,
    estimated,
};

pub const Order = enum {
    asc,
    desc,
};

pub const Range = struct {
    from: usize,
    to: usize,
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    owns_base_url: bool = false,
    relation: []const u8,
    api_key: []const u8,
    schema: []const u8,
    access_token: ?[]const u8 = null,
    params: std.ArrayList(http.QueryParam) = .empty,
    select_columns: ?[]const u8 = null,
    count: ?Count = null,
    range: ?Range = null,
    prefer_representation: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        base_url: []const u8,
        relation: []const u8,
        api_key: []const u8,
        schema: []const u8,
        access_token: ?[]const u8,
    ) Builder {
        return .{
            .allocator = allocator,
            .base_url = base_url,
            .relation = relation,
            .api_key = api_key,
            .schema = schema,
            .access_token = access_token,
        };
    }

    pub fn initOwned(
        allocator: std.mem.Allocator,
        base_url: []u8,
        relation: []const u8,
        api_key: []const u8,
        schema: []const u8,
        access_token: ?[]const u8,
    ) Builder {
        var out = init(allocator, base_url, relation, api_key, schema, access_token);
        out.owns_base_url = true;
        return out;
    }

    pub fn deinit(self: *Builder) void {
        if (self.owns_base_url) self.allocator.free(self.base_url);
        for (self.params.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.value);
        }
        self.params.deinit(self.allocator);
    }

    pub fn select(self: *Builder, columns: []const u8) !*Builder {
        self.select_columns = columns;
        return self;
    }

    pub fn eq(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "eq", value);
    }

    pub fn neq(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "neq", value);
    }

    pub fn gt(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "gt", value);
    }

    pub fn gte(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "gte", value);
    }

    pub fn lt(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "lt", value);
    }

    pub fn lte(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "lte", value);
    }

    pub fn like(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "like", value);
    }

    pub fn ilike(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "ilike", value);
    }

    pub fn is(self: *Builder, column: []const u8, value: []const u8) !*Builder {
        return try self.filter(column, "is", value);
    }

    pub fn orRaw(self: *Builder, expression: []const u8) !*Builder {
        try self.params.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, "or"),
            .value = try self.allocator.dupe(u8, expression),
        });
        return self;
    }

    pub fn inList(self: *Builder, column: []const u8, values: []const []const u8) !*Builder {
        var joined = std.ArrayList(u8).empty;
        defer joined.deinit(self.allocator);
        try joined.append(self.allocator, '(');
        for (values, 0..) |value, index| {
            if (index > 0) try joined.append(self.allocator, ',');
            try joined.appendSlice(self.allocator, value);
        }
        try joined.append(self.allocator, ')');
        return try self.filter(column, "in", joined.items);
    }

    pub fn order(self: *Builder, column: []const u8, direction: Order) !*Builder {
        const dir = switch (direction) {
            .asc => "asc",
            .desc => "desc",
        };
        const value = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ column, dir });
        errdefer self.allocator.free(value);
        try self.params.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, "order"),
            .value = value,
        });
        return self;
    }

    pub fn limit(self: *Builder, count_value: usize) !*Builder {
        return try self.appendIntParam("limit", count_value);
    }

    pub fn offset(self: *Builder, count_value: usize) !*Builder {
        return try self.appendIntParam("offset", count_value);
    }

    pub fn rangeItems(self: *Builder, from: usize, to: usize) *Builder {
        self.range = .{ .from = from, .to = to };
        return self;
    }

    pub fn countAs(self: *Builder, count: Count) *Builder {
        self.count = count;
        return self;
    }

    pub fn returningRepresentation(self: *Builder) *Builder {
        self.prefer_representation = true;
        return self;
    }

    pub fn buildUrlAlloc(self: *const Builder) ![]u8 {
        const relation_url = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.base_url, self.relation });
        errdefer self.allocator.free(relation_url);

        var params = std.ArrayList(http.QueryParam).empty;
        defer {
            for (params.items) |item| {
                self.allocator.free(item.name);
                self.allocator.free(item.value);
            }
            params.deinit(self.allocator);
        }

        if (self.select_columns) |columns| {
            try params.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, "select"),
                .value = try self.allocator.dupe(u8, columns),
            });
        }

        for (self.params.items) |item| {
            try params.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, item.name),
                .value = try self.allocator.dupe(u8, item.value),
            });
        }

        const out = try http.urlWithQueryAlloc(self.allocator, relation_url, params.items);
        self.allocator.free(relation_url);
        return out;
    }

    pub fn request(self: *const Builder) !OwnedRequest {
        const url = try self.buildUrlAlloc();
        errdefer self.allocator.free(url);

        var headers = http.OwnedHeaders.init(self.allocator);
        errdefer headers.deinit();

        try headers.appendApiKey(self.api_key);
        try headers.append("accept", "application/json");
        try headers.append("x-client-info", "fmus-zig/supabase");
        try headers.append("accept-profile", self.schema);
        try headers.appendBearer(self.access_token orelse self.api_key);
        if (self.count) |count| {
            try headers.append("Prefer", switch (count) {
                .exact => "count=exact",
                .planned => "count=planned",
                .estimated => "count=estimated",
            });
        }
        if (self.prefer_representation) {
            try headers.append("Prefer", "return=representation");
        }
        if (self.range) |r| {
            const range_value = try std.fmt.allocPrint(self.allocator, "{d}-{d}", .{ r.from, r.to });
            defer self.allocator.free(range_value);
            try headers.append("Range-Unit", "items");
            try headers.append("Range", range_value);
        }

        return .{
            .allocator = self.allocator,
            .url = url,
            .headers = headers,
            .request = http.get(url).header(headers.slice()),
        };
    }

    pub fn execute(self: *const Builder) !http.Response {
        var owned = try self.request();
        defer owned.deinit();
        return try owned.request.send(self.allocator);
    }

    pub fn jsonParse(self: *const Builder, comptime T: type) !T {
        var response = try self.execute();
        defer response.deinit();
        if (!response.ok()) return errors.Error.QueryFailed;
        return try response.jsonParse(T);
    }

    fn filter(self: *Builder, column: []const u8, operator: []const u8, value: []const u8) !*Builder {
        const filter_value = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ operator, value });
        errdefer self.allocator.free(filter_value);
        try self.params.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, column),
            .value = filter_value,
        });
        return self;
    }

    fn appendIntParam(self: *Builder, name: []const u8, value: usize) !*Builder {
        const rendered = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
        errdefer self.allocator.free(rendered);
        try self.params.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = rendered,
        });
        return self;
    }
};

pub const OwnedRequest = struct {
    allocator: std.mem.Allocator,
    url: []u8,
    headers: http.OwnedHeaders,
    request: http.Request,

    pub fn deinit(self: *OwnedRequest) void {
        self.allocator.free(self.url);
        self.headers.deinit();
    }
};

test "query builder builds select filter order and range request" {
    var builder = Builder.init(
        std.testing.allocator,
        "https://demo.supabase.co/rest/v1",
        "todos",
        "anon",
        "public",
        "access",
    );
    defer builder.deinit();

    _ = try (try (try builder.select("id,name")).eq("done", "false")).order("id", .desc);
    _ = try builder.limit(10);
    _ = builder.rangeItems(0, 9).countAs(.exact);

    var request = try builder.request();
    defer request.deinit();

    try std.testing.expect(std.mem.indexOf(u8, request.url, "select=id,name") != null);
    try std.testing.expect(std.mem.indexOf(u8, request.url, "done=eq.false") != null);
    try std.testing.expect(std.mem.indexOf(u8, request.url, "order=id.desc") != null);
    try std.testing.expect(std.mem.indexOf(u8, request.url, "limit=10") != null);
    try std.testing.expectEqualStrings("items", headerValue(request.headers.slice(), "range-unit").?);
    try std.testing.expectEqualStrings("count=exact", headerValue(request.headers.slice(), "prefer").?);
}

test "query builder supports raw or filter" {
    var builder = Builder.init(
        std.testing.allocator,
        "https://demo.supabase.co/rest/v1",
        "docs",
        "anon",
        "public",
        null,
    );
    defer builder.deinit();

    _ = try builder.orRaw("(title.ilike.*python*,content.ilike.*python*)");
    const url = try builder.buildUrlAlloc();
    defer std.testing.allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "or=") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "title.ilike.") != null);
}

fn headerValue(headers: []const http.Header, name: []const u8) ?[]const u8 {
    for (headers) |item| {
        if (std.ascii.eqlIgnoreCase(item.name, name)) return item.value;
    }
    return null;
}
