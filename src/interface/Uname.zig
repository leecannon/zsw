const std = @import("std");

const System = @import("System.zig");

pub const Uname = union(enum) {
    host: std.os.utsname,
    custom: CustomUname,

    pub const CustomUname = struct {
        operating_system_name: []const u8,
        host_name: []const u8,
        /// The operating system release
        release: []const u8,
        /// The operating system version
        version: []const u8,
        hardware_identifier: []const u8,
        domain_name: []const u8,
    };
};

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
