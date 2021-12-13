const std = @import("std");

const System = @import("System.zig").System;
const File = @import("File.zig").File;
const Entry = @import("../backend/FileSystem.zig").Entry;

pub const Dir = struct {
    system: System,
    data: Data,

    pub const Data = extern union {
        host: std.fs.Dir,
        custom: Custom,

        pub const Custom = struct {
            entry: *Entry,
        };
    };

    pub inline fn openFile(self: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
        return try self.system.vtable.openFileFromDir(self.system, self, sub_path, flags);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
