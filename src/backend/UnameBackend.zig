const std = @import("std");

const Config = @import("../config/Config.zig");
const Uname = @import("../interface/Uname.zig").Uname;

pub fn UnameBackend(comptime config: Config) type {
    if (!config.uname) return struct {};

    return struct {
        allocator: std.mem.Allocator,

        operating_system_name: []const u8,

        host_name: []const u8,

        /// The operating system release
        release: []const u8,

        /// The operating system version
        version: []const u8,

        hardware_identifier: []const u8,

        domain_name: []const u8,

        const Self = @This();
        const log = std.log.scoped(config.logging_scope);

        pub fn uname(self: *Self) Uname {
            // TODO: This is a memory leak

            const result: Uname = .{
                .operating_system_name = self.operating_system_name,
                .host_name = self.host_name,
                .release = self.release,
                .version = self.version,
                .hardware_identifier = self.hardware_identifier,
                .domain_name = self.domain_name,
            };

            if (config.log) {
                log.debug("uname called, returning {}", .{result});
            }

            return result;
        }
    };
}

comptime {
    @import("../internal.zig").referenceAllIterations(UnameBackend);
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
