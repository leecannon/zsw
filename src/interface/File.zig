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

pub inline fn close(self: File) void {
    return self.system.vtable.closeFile(self.system, self);
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
