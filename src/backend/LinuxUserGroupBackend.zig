const std = @import("std");

const Config = @import("../config/Config.zig");

pub fn LinuxUserGroupBackend(comptime config: Config) type {
    if (!config.linux_user_group) return struct {};

    return struct {
        /// Effective user id
        euid: std.os.uid_t,

        const Self = @This();
        const log = std.log.scoped(config.logging_scope);

        pub fn osLinuxGeteuid(self: *Self) std.os.uid_t {
            if (config.log) {
                log.debug("osLinuxGeteuid called, returning {}", .{self.euid});
            }

            return self.euid;
        }
    };
}

comptime {
    @import("../internal.zig").referenceAllIterations(LinuxUserGroupBackend);
}

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
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
