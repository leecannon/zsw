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

pub inline fn stat(self: Dir) File.StatError!File.Stat {
    return self.system.vtable.statDir(self.system, self);
}

pub inline fn updateTimes(self: Dir, atime: i128, mtime: i128) File.UpdateTimesError!void {
    return self.system.vtable.updateTimesDir(self.system, self, atime, mtime);
}

comptime {
    std.testing.refAllDecls(@This());
}
