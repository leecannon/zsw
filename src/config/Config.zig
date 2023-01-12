const std = @import("std");
const Config = @This();

/// Should the backend emit log messages
/// Messages are only logged for enabled capabilities
log: bool = false,

/// The `std.log` scope to use
logging_scope: @Type(.EnumLiteral) = .zsw,

/// If the requested capability is not enabled and this is `true` the request is forwarded
/// to the host, if this is `false` panic
fallback_to_host: bool = true,

/// Enable file system capability
///
/// If this capability is enabled the `arguments` parameter to `init` requires
/// a `file_system` field of type `*const FileSystemDescription`
file_system: bool = false,

/// Enable linux user and group capability
///
/// If this capability is enabled the `arguments` parameter to `init` requires
/// a `linux_user_group` field of type `LinuxUserGroupDescription`
linux_user_group: bool = false,

/// Enable uname capability.
///
/// If this capability is enabled the `arguments` parameter to `init` requires
/// a `uname` field of type `UnameDescription`
uname: bool = false,

/// Enable time capability
///
/// If this capability is enabled the `arguments` parameter to `init` requires
/// a `time` field of type `TimeDescription`
time: bool = false,

// TODO: Actually implement this
thread_safe: bool = false,

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
