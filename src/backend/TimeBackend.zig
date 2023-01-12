const std = @import("std");

const Config = @import("../config/Config.zig");

pub fn TimeBackend(comptime config: Config) type {
    if (!config.time) return struct {};

    return struct {
        /// A pointer to the source to be used as the current time in nanoseconds.
        nano_timestamp: *const i128,

        const Self = @This();
        const log = std.log.scoped(config.logging_scope);

        /// Get a calendar timestamp, in nanoseconds, relative to UTC 1970-01-01.
        ///
        /// See `std.time.nanoTimestamp`
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
    @import("../internal.zig").referenceAllIterations(TimeBackend);
}

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            if (@TypeOf(@field(T, decl.name)) == type) {
                switch (@typeInfo(@field(T, decl.name))) {
                    .Struct, .Enum, .Union, .Opaque => {
                        refAllDeclsRecursive(@field(T, decl.name));
                        _ = @field(T, decl.name);
                    },
                    .Type, .Fn => {
                        _ = @field(T, decl.name);
                    },
                    else => {},
                }
            }
        }
    }
}
