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

    // Exposed by `File`
    readFile: *const fn (ptr: System, file: File, buffer: []u8) std.os.ReadError!usize,
    closeFile: *const fn (ptr: System, file: File) void,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
