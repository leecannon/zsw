const std = @import("std");
const interface = @import("interface.zig");

pub const Dir = struct {
    _sys: interface.Sys,
    _value: Value,

    const Value = extern union {
        system: std.fs.Dir,
        custom: void,
    };

    pub inline fn openFile(self: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
        return self._sys._vtable.openFileFromDirFn(self._sys._ptr, self, sub_path, flags);
    }
};

pub const File = struct {
    _sys: interface.Sys,
    _value: Value,

    const Value = extern union {
        system: std.fs.File,
        custom: void,
    };

    pub const OpenFlags = std.fs.File.OpenFlags;
    pub const OpenError = std.fs.File.OpenError;

    pub inline fn close(self: File) void {
        return self._sys._vtable.closeFileFn(self._sys._ptr, self);
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
