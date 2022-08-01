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

// TODO: Is providing os specific functionality on the top level like this a good idea?
// `usingnamespace`, `@compileError`, etc
pub inline fn geteuid(self: System) std.os.uid_t {
    return self.vtable.osLinuxGeteuid(self);
}

pub const VTable = struct {
    // Exposed by `System`
    cwd: if (builtin.zig_backend == .stage1)
        fn (ptr: System) Dir
    else
        *const fn (ptr: System) Dir,

    osLinuxGeteuid: if (builtin.zig_backend == .stage1)
        fn (ptr: System) std.os.uid_t
    else
        *const fn (ptr: System) std.os.uid_t,

    // Exposed by `Dir`
    openFileFromDir: if (builtin.zig_backend == .stage1)
        fn (ptr: System, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File
    else
        *const fn (ptr: System, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File,

    // Exposed by `File`
    readFile: if (builtin.zig_backend == .stage1)
        fn (ptr: System, file: File, buffer: []u8) std.os.ReadError!usize
    else
        *const fn (ptr: System, file: File, buffer: []u8) std.os.ReadError!usize,

    closeFile: if (builtin.zig_backend == .stage1)
        fn (ptr: System, file: File) void
    else
        *const fn (ptr: System, file: File) void,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
