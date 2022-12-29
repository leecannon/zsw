const std = @import("std");

const System = @import("System.zig");
const File = @This();

_system: System,
_data: Data,

pub const Data = union {
    host: std.fs.File,
    custom: *anyopaque,
};

pub const OpenFlags = std.fs.File.OpenFlags;
pub const OpenError = std.fs.File.OpenError;

pub const CreateFlags = std.fs.File.CreateFlags;

/// Close the file and deallocate any related resources.
///
/// See `std.fs.File.close`
pub inline fn close(self: File) void {
    return self._system._vtable.closeFile(self._system, self);
}

pub const Stat = std.fs.File.Stat;
pub const StatError = std.fs.File.StatError;

/// Returns various statistics of the file.
///
/// See `std.fs.File.stat`
pub inline fn stat(self: File) StatError!Stat {
    return self._system._vtable.statFile(self._system, self);
}

pub const UpdateTimesError = std.fs.File.UpdateTimesError;

/// Update the access time (atime) and modification time (mtime) of the file.
///
/// See `std.fs.File.updateTimes`
pub inline fn updateTimes(self: File, atime: i128, mtime: i128) UpdateTimesError!void {
    return self._system._vtable.updateTimesFile(self._system, self, atime, mtime);
}

pub const Reader = std.io.Reader(File, std.os.ReadError, read);

/// Returns a `std.io.Reader` wrapping this file.
pub fn reader(file: File) Reader {
    return .{ .context = file };
}

/// Read from the file into the given buffer.
/// Returns the amount of bytes written to the buffer.
///
/// See `std.fs.File.read`
pub fn read(self: File, buffer: []u8) std.os.ReadError!usize {
    return self._system._vtable.readFile(self._system, self, buffer);
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
