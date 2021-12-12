const std = @import("std");
const interface = @import("interface.zig");
const System = interface.System;

const types = @import("types.zig");
const Dir = types.Dir;
const File = types.File;

pub const Config = struct {
    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub fn CustomBackend(comptime backend_config: Config) type {
    _ = backend_config;

    return struct {
        allocator: std.mem.Allocator,

        const Self = @This();
        const alignment = @alignOf(Self);

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub inline fn system(self: *Self) System {
            return .{
                ._ptr = self,
                ._vtable = &vtable,
            };
        }

        fn cwd(self: *Self) Dir {
            _ = self;
            @panic("unimplemented");
        }

        fn openFileFromDir(self: *Self, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
            _ = self;
            _ = dir;
            _ = sub_path;
            _ = flags;
            @panic("unimplemented");
        }

        fn readFile(self: *Self, file: File, buffer: []u8) std.os.ReadError!usize {
            _ = self;
            _ = file;
            _ = buffer;
            @panic("unimplemented");
        }

        fn closeFile(self: *Self, file: File) void {
            _ = self;
            _ = file;
            @panic("unimplemented");
        }

        fn osLinuxGeteuid(self: *Self) std.os.linux.uid_t {
            _ = self;
            @panic("unimplemented");
        }

        const vtable: interface.VTable = blk: {
            const gen = struct {
                fn cwdEntry(ptr: *c_void) Dir {
                    return @call(.{ .modifier = .always_inline }, cwd, .{
                        @ptrCast(*Self, @alignCast(alignment, ptr)),
                    });
                }

                fn openFileFromDirEntry(ptr: *c_void, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
                    return @call(.{ .modifier = .always_inline }, openFileFromDir, .{
                        @ptrCast(*Self, @alignCast(alignment, ptr)),
                        dir,
                        sub_path,
                        flags,
                    });
                }

                fn readFileEntry(ptr: *c_void, file: File, buffer: []u8) std.os.ReadError!usize {
                    return @call(.{ .modifier = .always_inline }, readFile, .{
                        @ptrCast(*Self, @alignCast(alignment, ptr)),
                        file,
                        buffer,
                    });
                }

                fn closeEntry(ptr: *c_void, file: File) void {
                    return @call(.{ .modifier = .always_inline }, closeFile, .{
                        @ptrCast(*Self, @alignCast(alignment, ptr)),
                        file,
                    });
                }

                fn osLinuxGeteuidEntry(ptr: *c_void) std.os.linux.uid_t {
                    return @call(.{ .modifier = .always_inline }, osLinuxGeteuid, .{
                        @ptrCast(*Self, @alignCast(alignment, ptr)),
                    });
                }
            };

            break :blk .{
                .cwdFn = gen.cwdEntry,
                .openFileFromDirFn = gen.openFileFromDirEntry,
                .readFileFn = gen.readFileEntry,
                .closeFileFn = gen.closeEntry,
                .osLinuxGeteuidFn = gen.osLinuxGeteuidEntry,
            };
        };

        comptime {
            std.testing.refAllDecls(@This());
        }
    };
}

pub const HostBackend = struct {
    pub const system: interface.System = .{
        ._ptr = undefined,
        ._vtable = &interface.VTable{
            .cwdFn = cwd,
            .openFileFromDirFn = openFileFromDir,
            .readFileFn = readFile,
            .closeFileFn = closeFile,
            .osLinuxGeteuidFn = osLinuxGeteuid,
        },
    };

    fn cwd(_: *c_void) Dir {
        return .{
            ._system = system,
            ._value = .{ .host = std.fs.cwd() },
        };
    }

    fn openFileFromDir(_: *c_void, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
        return File{
            ._system = system,
            ._value = .{ .host = try dir._value.host.openFile(sub_path, flags) },
        };
    }

    fn readFile(_: *c_void, file: File, buffer: []u8) std.os.ReadError!usize {
        return file._value.host.read(buffer);
    }

    fn closeFile(_: *c_void, file: File) void {
        file._value.host.close();
    }

    fn osLinuxGeteuid(_: *c_void) std.os.linux.uid_t {
        return std.os.linux.geteuid();
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
