const std = @import("std");

// ** CONFIGURATION

pub const Config = @import("config/Config.zig");
pub const FileSystemDescription = @import("config/FileSystemDescription.zig");
pub const LinuxUserGroupDescription = @import("config/LinuxUserGroupDescription.zig");
pub const TimeDescription = @import("config/TimeDescription.zig");

// ** CUSTOM BACKEND

const backend = @import("backend/Backend.zig");
pub const Backend = backend.Backend;

// ** SYSTEM BACKEND

/// This system calls the host directly
pub const host_system: System = @import("backend/host_backend.zig").host_system;

// ** INTERFACE

pub const System = @import("interface/System.zig");
pub const Dir = @import("interface/Dir.zig");
pub const File = @import("interface/File.zig");
pub const Uname = @import("interface/Uname.zig").Uname;

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
