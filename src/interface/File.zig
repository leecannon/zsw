const std = @import("std");

const System = @import("System.zig");
const File = @This();

system: System,
data: Data,

pub const Data = union {
    host: std.fs.File,
    custom: *anyopaque,
};

pub const OpenFlags = std.fs.File.OpenFlags;
pub const OpenError = std.fs.File.OpenError;

pub const CreateFlags = std.fs.File.CreateFlags;

pub inline fn close(self: File) void {
    return self.system.vtable.closeFile(self.system, self);
}

pub const Stat = std.fs.File.Stat;
pub const StatError = std.fs.File.StatError;

pub inline fn stat(self: File) StatError!Stat {
    return self.system.vtable.statFile(self.system, self);
}

pub const UpdateTimesError = std.fs.File.UpdateTimesError;

pub inline fn updateTimes(self: File, atime: i128, mtime: i128) UpdateTimesError!void {
    return self.system.vtable.updateTimesFile(self.system, self, atime, mtime);
}

pub const Reader = std.io.Reader(File, std.os.ReadError, read);

pub fn reader(file: File) Reader {
    return .{ .context = file };
}

pub fn read(self: File, buffer: []u8) std.os.ReadError!usize {
    return self.system.vtable.readFile(self.system, self, buffer);
}

comptime {
    std.testing.refAllDecls(@This());
}
