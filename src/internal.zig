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
