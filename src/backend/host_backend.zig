const std = @import("std");

const System = @import("../interface/System.zig").System;
const Dir = @import("../interface/Dir.zig").Dir;
const File = @import("../interface/File.zig").File;

pub fn cwd(system: System) Dir {
    return .{
        .system = system,
        .data = .{ .host = std.fs.cwd() },
    };
}

pub fn openFileFromDir(system: System, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
    return File{
        .system = system,
        .data = .{ .host = try dir.data.host.openFile(sub_path, flags) },
    };
}

pub fn readFile(system: System, file: File, buffer: []u8) std.os.ReadError!usize {
    _ = system;
    return try file.data.host.read(buffer);
}

pub fn closeFile(system: System, file: File) void {
    _ = system;
    file.data.host.close();
}

pub fn osLinuxGeteuid(system: System) std.os.uid_t {
    _ = system;
    return std.os.linux.geteuid();
}

pub const host_system: System = .{
    .ptr = undefined,
    .vtable = &System.VTable{
        .cwd = cwd,
        .openFileFromDir = openFileFromDir,
        .readFile = readFile,
        .closeFile = closeFile,
        .osLinuxGeteuid = osLinuxGeteuid,
    },
};

comptime {
    std.testing.refAllDecls(@This());
}
