const std = @import("std");

const Dir = @import("Dir.zig");
const File = @import("File.zig");
const builtin = @import("builtin");
const System = @This();

_ptr: *anyopaque,
_vtable: *const VTable,

/// Returns a handle to the current working directory
///
/// See `std.fs.cwd`
pub inline fn cwd(self: System) Dir {
    return self._vtable.cwd(self);
}

/// Get a calendar timestamp, in nanoseconds, relative to UTC 1970-01-01.
///
/// See `std.time.nanoTimestamp`
pub inline fn nanoTimestamp(self: System) i128 {
    return self._vtable.nanoTimestamp(self);
}

/// Get the current effective user id.
///
/// See `std.os.linux.geteuid`
pub inline fn geteuid(self: System) std.os.uid_t {
    // TODO: Is providing os specific functionality on the top level like this a good idea?
    // `usingnamespace`, `@compileError`, etc
    return self._vtable.osLinuxGeteuid(self);
}

pub const VTable = struct {
    // Exposed by `System`
    cwd: *const fn (ptr: System) Dir,
    nanoTimestamp: *const fn (self: System) i128,

    osLinuxGeteuid: *const fn (ptr: System) std.os.uid_t,

    // Exposed by `Dir`
    openFileFromDir: *const fn (
        ptr: System,
        dir: Dir,
        sub_path: []const u8,
        flags: File.OpenFlags,
    ) File.OpenError!File,
    createFileFromDir: *const fn (
        ptr: System,
        dir: Dir,
        sub_path: []const u8,
        flags: File.CreateFlags,
    ) File.OpenError!File,
    statDir: *const fn (ptr: System, dir: Dir) File.StatError!File.Stat,
    updateTimesDir: *const fn (
        ptr: System,
        dir: Dir,
        atime: i128,
        mtime: i128,
    ) File.UpdateTimesError!void,

    // Exposed by `File`
    readFile: *const fn (ptr: System, file: File, buffer: []u8) std.os.ReadError!usize,
    statFile: *const fn (ptr: System, file: File) File.StatError!File.Stat,
    updateTimesFile: *const fn (
        ptr: System,
        file: File,
        atime: i128,
        mtime: i128,
    ) File.UpdateTimesError!void,
    closeFile: *const fn (ptr: System, file: File) void,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
