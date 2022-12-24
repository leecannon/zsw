const std = @import("std");

const System = @import("../interface/System.zig");
const Dir = @import("../interface/Dir.zig");
const File = @import("../interface/File.zig");

pub fn cwd(system: System) Dir {
    return .{
        .system = system,
        .data = .{ .host = std.fs.cwd() },
    };
}

pub fn nanoTimestamp(system: System) i128 {
    _ = system;
    return std.time.nanoTimestamp();
}

pub fn osLinuxGeteuid(system: System) std.os.uid_t {
    _ = system;
    return std.os.linux.geteuid();
}

pub fn openFileFromDir(system: System, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
    return File{
        .system = system,
        .data = .{ .host = try dir.data.host.openFile(sub_path, flags) },
    };
}

pub fn statDir(system: System, dir: Dir) File.StatError!File.Stat {
    _ = system;
    return dir.data.host.stat();
}

pub fn updateTimesDir(system: System, dir: Dir, atime: i128, mtime: i128) File.UpdateTimesError!void {
    _ = mtime;
    _ = atime;
    _ = dir;
    _ = system;
    @panic("The Zig std lib does not implement `updateTimes` for directores *yet*"); // TODO
}

pub fn readFile(system: System, file: File, buffer: []u8) std.os.ReadError!usize {
    _ = system;
    return file.data.host.read(buffer);
}

pub fn statFile(system: System, file: File) File.StatError!File.Stat {
    _ = system;
    return file.data.host.stat();
}

pub fn updateTimesFile(system: System, file: File, atime: i128, mtime: i128) File.UpdateTimesError!void {
    _ = system;
    return file.data.host.updateTimes(atime, mtime);
}

pub fn closeFile(system: System, file: File) void {
    _ = system;
    file.data.host.close();
}

pub const host_system: System = .{
    .ptr = undefined,
    .vtable = &System.VTable{
        .cwd = cwd,
        .nanoTimestamp = nanoTimestamp,
        .osLinuxGeteuid = osLinuxGeteuid,
        .openFileFromDir = openFileFromDir,
        .statDir = statDir,
        .updateTimesDir = updateTimesDir,
        .readFile = readFile,
        .statFile = statFile,
        .updateTimesFile = updateTimesFile,
        .closeFile = closeFile,
    },
};

comptime {
    std.testing.refAllDecls(@This());
}
