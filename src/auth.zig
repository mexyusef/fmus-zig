const std = @import("std");

pub const Mode = enum {
    api_key,
    oauth,
    token,
};

pub const Profile = struct {
    id: []const u8,
    provider: []const u8,
    mode: Mode,
    label: ?[]const u8 = null,
    secret_ref: ?[]const u8 = null,
    is_default: bool = false,
};

pub fn defaultForProvider(profiles: []const Profile, provider: []const u8) ?Profile {
    var fallback: ?Profile = null;
    for (profiles) |profile| {
        if (!std.mem.eql(u8, profile.provider, provider)) continue;
        if (profile.is_default) return profile;
        if (fallback == null) fallback = profile;
    }
    return fallback;
}

pub fn describe(profile: Profile) []const u8 {
    return switch (profile.mode) {
        .api_key => "api_key",
        .oauth => "oauth",
        .token => "token",
    };
}

test "default profile resolves" {
    const profiles = [_]Profile{
        .{ .id = "a", .provider = "openai", .mode = .api_key },
        .{ .id = "b", .provider = "openai", .mode = .oauth, .is_default = true },
    };
    try std.testing.expectEqualStrings("b", defaultForProvider(&profiles, "openai").?.id);
}
