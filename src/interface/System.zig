const std = @import("std");

const Dir = @import("Dir.zig");
const File = @import("File.zig");
const builtin = @import("builtin");
const System = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub inline fn cwd(self: System) Dir {
    return self.vtable.cwd(self);
}

pub inline fn nanoTimestamp(self: System) i128 {
    return self.vtable.nanoTimestamp(self);
}

// TODO: Is providing os specific functionality on the top level like this a good idea?
// `usingnamespace`, `@compileError`, etc
pub inline fn geteuid(self: System) std.os.uid_t {
    return self.vtable.osLinuxGeteuid(self);
}

pub const VTable = struct {
    // Exposed by `System`
    cwd: *const fn (ptr: System) Dir,
    nanoTimestamp: *const fn (self: System) i128,

    osLinuxGeteuid: *const fn (ptr: System) std.os.uid_t,

    // Exposed by `Dir`
    openFileFromDir: *const fn (ptr: System, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File,
    statDir: *const fn (ptr: System, dir: Dir) File.StatError!File.Stat,
    updateTimesDir: *const fn (ptr: System, dir: Dir, atime: i128, mtime: i128) File.UpdateTimesError!void,

    // Exposed by `File`
    readFile: *const fn (ptr: System, file: File, buffer: []u8) std.os.ReadError!usize,
    statFile: *const fn (ptr: System, file: File) File.StatError!File.Stat,
    updateTimesFile: *const fn (ptr: System, file: File, atime: i128, mtime: i128) File.UpdateTimesError!void,
    closeFile: *const fn (ptr: System, file: File) void,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
