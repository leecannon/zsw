const std = @import("std");

const Config = @import("../config/Config.zig");

pub fn Time(comptime config: Config) type {
    if (!config.time) return struct {};

    return struct {
        /// A pointer to the source to be used as the current time in nanoseconds.
        nano_timestamp: *const i128,

        const Self = @This();
        const log = std.log.scoped(config.logging_scope);

        pub fn nanoTimestamp(self: *const Self) i128 {
            const value = @atomicLoad(i128, self.nano_timestamp, .Acquire);

            if (config.log) {
                log.debug("nanoTimestamp called, returning {}", .{value});
            }

            return value;
        }
    };
}

comptime {
    @import("../internal.zig").referenceAllIterations(Time);
}

comptime {
    std.testing.refAllDecls(@This());
}
