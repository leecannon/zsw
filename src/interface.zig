const std = @import("std");

const types = @import("types.zig");
const Dir = types.Dir;
const File = types.File;

pub const VTable = struct {
    // Exposed by `System`
    cwdFn: fn (ptr: *c_void) Dir,
    osLinuxGeteuidFn: fn (ptr: *c_void) std.os.linux.uid_t,

    // Exposed by `Dir`
    openFileFromDirFn: fn (ptr: *c_void, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File,

    // Exposed by `File`
    readFileFn: fn (ptr: *c_void, file: File, buffer: []u8) std.os.ReadError!usize,
    closeFileFn: fn (ptr: *c_void, file: File) void,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const System = struct {
    _ptr: *c_void,
    _vtable: *const VTable,

    pub inline fn cwd(self: System) Dir {
        return self._vtable.cwdFn(self._ptr);
    }

    // TODO: Is providing os specific functionality on the top level like this a good idea?
    // `usingnamespace`, `@compileError`, etc
    pub inline fn geteuid(self: System) std.os.linux.uid_t {
        return self._vtable.osLinuxGeteuidFn(self._ptr);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
