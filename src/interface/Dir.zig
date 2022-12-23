const std = @import("std");

const System = @import("System.zig");
const File = @import("File.zig");
const Dir = @This();

system: System,
data: Data,

pub const Data = union {
    host: std.fs.Dir,
    custom: *anyopaque,
};

pub inline fn openFile(self: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
    return self.system.vtable.openFileFromDir(self.system, self, sub_path, flags);
}

comptime {
    std.testing.refAllDecls(@This());
}
