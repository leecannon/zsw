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

/// If `null` is provided then the host system is used directly
pub fn Backend(comptime backend_config: ?Config) type {
    return struct {
        _: usize = 0,

        const Self = @This();
        const alignment = @alignOf(Self);

        pub inline fn system(self: *Self) System {
            return .{
                ._ptr = self,
                ._vtable = &vtable,
            };
        }

        fn cwd(self: *Self) Dir {
            if (backend_config) |config| {
                _ = config;
                @panic("unimplemented");
            }
            return .{
                ._system = self.system(),
                ._value = .{ .host = std.fs.cwd() },
            };
        }

        fn openFileFromDir(self: *Self, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
            if (backend_config) |config| {
                _ = config;
                @panic("unimplemented");
            }
            return File{
                ._system = self.system(),
                ._value = .{ .host = try dir._value.host.openFile(sub_path, flags) },
            };
        }

        fn readFile(self: *Self, file: File, buffer: []u8) std.os.ReadError!usize {
            if (backend_config) |config| {
                _ = self;
                _ = config;
                @panic("unimplemented");
            }
            return file._value.host.read(buffer);
        }

        fn closeFile(self: *Self, file: File) void {
            if (backend_config) |config| {
                _ = self;
                _ = config;
                @panic("unimplemented");
            }
            file._value.host.close();
        }

        fn osLinuxGeteuid(self: *Self) std.os.linux.uid_t {
            if (backend_config) |config| {
                _ = self;
                _ = config;
                @panic("unimplemented");
            }
            return std.os.linux.geteuid();
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

comptime {
    std.testing.refAllDecls(@This());
}
