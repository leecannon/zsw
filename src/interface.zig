const std = @import("std");

const types = @import("types.zig");
const Dir = types.Dir;
const File = types.File;

pub const VTable = struct {
    // Exposed by `Sys`
    cwdFn: fn (ptr: *c_void) Dir,

    // Exposed by `Dir`
    openFileFromDirFn: fn (ptr: *c_void, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File,

    // Exposed by `File`
    closeFileFn: fn (ptr: *c_void, file: File) void,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const Sys = struct {
    _ptr: *c_void,
    _vtable: *const VTable,

    pub inline fn cwd(self: Sys) Dir {
        return self._vtable.cwdFn(self._ptr);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
