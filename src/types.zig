const std = @import("std");
const interface = @import("interface.zig");

pub const Dir = struct {
    _system: interface.System,
    _value: Value,

    const Value = extern union {
        host: std.fs.Dir,
        custom: void,
    };

    pub inline fn openFile(self: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
        return self._system._vtable.openFileFromDirFn(self._system._ptr, self, sub_path, flags);
    }
};

pub const File = struct {
    _system: interface.System,
    _value: Value,

    const Value = extern union {
        host: std.fs.File,
        custom: void,
    };

    pub const OpenFlags = std.fs.File.OpenFlags;
    pub const OpenError = std.fs.File.OpenError;

    pub inline fn close(self: File) void {
        return self._system._vtable.closeFileFn(self._system._ptr, self);
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
