const std = @import("std");
const Config = @import("config/Config.zig");

pub fn referenceAllIterations(comptime TypeFunc: anytype) void {
    // TODO: Is there a better way to do this?

    inline for (&[_]bool{ false, true }) |time| {
        inline for (&[_]bool{ false, true }) |thread_safe| {
            inline for (&[_]bool{ false, true }) |fallback_to_host| {
                _ = TypeFunc(Config{
                    .log = true,
                    .file_system = true,
                    .linux_user_group = true,
                    .time = time,
                    .thread_safe = thread_safe,
                    .fallback_to_host = fallback_to_host,
                });
            }
        }
    }
}

comptime {
    std.testing.refAllDecls(@This());
}
