const std = @import("std");

const System = @import("../interface/System.zig");
const Dir = @import("../interface/Dir.zig");
const File = @import("../interface/File.zig");
const Uname = @import("../interface/Uname.zig").Uname;

/// See `std.fs.cwd`
pub fn cwd(system: System) Dir {
    return .{
        ._system = system,
        ._data = .{ .host = std.fs.cwd() },
    };
}

/// See `std.time.nanoTimestamp`
pub fn nanoTimestamp(system: System) i128 {
    _ = system;
    return std.time.nanoTimestamp();
}

/// See `std.os.linux.geteuid`
pub fn osLinuxGeteuid(system: System) std.os.uid_t {
    _ = system;
    return std.os.linux.geteuid();
}

/// See `std.os.uname`
pub fn uname(system: System) Uname {
    _ = system;
    return .{ .host = std.os.uname() };
}

/// See `std.io.getStdIn`
pub fn getStdIn(system: System) File {
    return .{
        ._system = system,
        ._data = .{ .host = std.io.getStdIn() },
    };
}

/// See `std.io.getStdErr`
pub fn getStdErr(system: System) File {
    return .{
        ._system = system,
        ._data = .{ .host = std.io.getStdErr() },
    };
}

/// See `std.io.getStdOut`
pub fn getStdOut(system: System) File {
    return .{
        ._system = system,
        ._data = .{ .host = std.io.getStdOut() },
    };
}

/// See `std.fs.Dir.openFile`
pub fn openFileFromDir(
    system: System,
    dir: Dir,
    sub_path: []const u8,
    flags: File.OpenFlags,
) File.OpenError!File {
    return .{
        ._system = system,
        ._data = .{ .host = try dir._data.host.openFile(sub_path, flags) },
    };
}

/// See `std.fs.Dir.createFile`
pub fn createFileFromDir(
    system: System,
    dir: Dir,
    sub_path: []const u8,
    flags: File.CreateFlags,
) File.OpenError!File {
    return .{
        ._system = system,
        ._data = .{ .host = try dir._data.host.createFile(sub_path, flags) },
    };
}

/// See `std.fs.Dir.stat`
pub fn statDir(system: System, dir: Dir) File.StatError!File.Stat {
    _ = system;
    return dir._data.host.stat();
}

/// Not implemented by the zig std lib
pub fn updateTimesDir(
    system: System,
    dir: Dir,
    atime: i128,
    mtime: i128,
) File.UpdateTimesError!void {
    _ = mtime;
    _ = atime;
    _ = dir;
    _ = system;
    @panic("The Zig std lib does not implement `updateTimes` for directores *yet*"); // TODO
}

/// See `std.fs.File.read`
pub fn readFile(system: System, file: File, buffer: []u8) std.os.ReadError!usize {
    _ = system;
    return file._data.host.read(buffer);
}

/// See `std.fs.File.stat`
pub fn statFile(system: System, file: File) File.StatError!File.Stat {
    _ = system;
    return file._data.host.stat();
}

/// See `std.fs.File.updateTimes`
pub fn updateTimesFile(
    system: System,
    file: File,
    atime: i128,
    mtime: i128,
) File.UpdateTimesError!void {
    _ = system;
    return file._data.host.updateTimes(atime, mtime);
}

/// See `std.fs.File.close`
pub fn closeFile(system: System, file: File) void {
    _ = system;
    file._data.host.close();
}

pub const host_system: System = .{
    ._ptr = undefined,
    ._vtable = &System.VTable{
        .cwd = cwd,
        .nanoTimestamp = nanoTimestamp,
        .osLinuxGeteuid = osLinuxGeteuid,
        .uname = uname,
        .getStdIn = getStdIn,
        .getStdErr = getStdErr,
        .getStdOut = getStdOut,
        .openFileFromDir = openFileFromDir,
        .createFileFromDir = createFileFromDir,
        .statDir = statDir,
        .updateTimesDir = updateTimesDir,
        .readFile = readFile,
        .statFile = statFile,
        .updateTimesFile = updateTimesFile,
        .closeFile = closeFile,
    },
};

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            if (@TypeOf(@field(T, decl.name)) == type) {
                switch (@typeInfo(@field(T, decl.name))) {
                    .Struct, .Enum, .Union, .Opaque => {
                        refAllDeclsRecursive(@field(T, decl.name));
                        _ = @field(T, decl.name);
                    },
                    .Type, .Fn => {
                        _ = @field(T, decl.name);
                    },
                    else => {},
                }
            }
        }
    }
}
