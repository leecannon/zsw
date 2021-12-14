const std = @import("std");

const System = @import("System.zig").System;

pub const File = struct {
    system: System,
    data: Data,

    pub const Data = extern union {
        host: std.fs.File,
        custom: Custom,

        pub const Custom = struct {
            entry: *c_void,
            view_index: u32,
        };
    };

    pub const OpenFlags = std.fs.File.OpenFlags;
    pub const OpenError = std.fs.File.OpenError;

    pub inline fn close(self: File) void {
        return self.system.vtable.closeFile(self.system, self);
    }

    pub const Reader = std.io.Reader(File, std.os.ReadError, read);

    pub fn reader(file: File) Reader {
        return .{ .context = file };
    }

    pub fn read(self: File, buffer: []u8) std.os.ReadError!usize {
        return try self.system.vtable.readFile(self.system, self, buffer);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
