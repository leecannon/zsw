const std = @import("std");

const System = @import("System.zig");
const File = @import("File.zig");
const Dir = @This();

_system: System,
_data: Data,

pub const Data = union {
    host: std.fs.Dir,
    custom: *anyopaque,
};

/// Opens a file for reading or writing, without attempting to create a new file.
/// To create a new file, see `createFile`.
/// Call `File.close` to release the resource.
///
/// See `std.fs.Dir.openFile`
pub inline fn openFile(self: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
    return self._system._vtable.openFileFromDir(self._system, self, sub_path, flags);
}

/// Creates, opens, or overwrites a file with write access.
/// Call `File.close` on the result when done.
/// See `std.fs.Dir.createFile`
pub inline fn createFile(self: Dir, sub_path: []const u8, flags: File.CreateFlags) File.OpenError!File {
    return self._system._vtable.createFileFromDir(self._system, self, sub_path, flags);
}

/// Returns various statistics of the directory.
pub inline fn stat(self: Dir) File.StatError!File.Stat {
    return self._system._vtable.statDir(self._system, self);
}

/// Update the access time (atime) and modification time (mtime) of the directory.
pub inline fn updateTimes(self: Dir, atime: i128, mtime: i128) File.UpdateTimesError!void {
    return self._system._vtable.updateTimesDir(self._system, self, atime, mtime);
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
