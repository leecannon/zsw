const std = @import("std");
const interface = @import("interface.zig");

const types = @import("types.zig");
const Dir = types.Dir;
const File = types.File;

pub const Config = struct {
    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// If `null` is provided then the system is used directly
pub fn Backend(comptime backend_config: ?Config) type {
    return struct {
        _: usize = 0,

        const Self = @This();
        const alignment = @alignOf(Self);

        pub inline fn sys(self: *Self) interface.Sys {
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
                ._sys = self.sys(),
                ._value = .{ .system = std.fs.cwd() },
            };
        }

        fn openFileFromDir(self: *Self, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
            if (backend_config) |config| {
                _ = config;
                @panic("unimplemented");
            }
            return File{
                ._sys = self.sys(),
                ._value = .{ .system = try dir._value.system.openFile(sub_path, flags) },
            };
        }

        fn closeFile(self: *Self, file: File) void {
            _ = self;
            if (backend_config) |config| {
                _ = config;
                @panic("unimplemented");
            }
            file._value.system.close();
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

                fn closeEntry(ptr: *c_void, file: File) void {
                    return @call(.{ .modifier = .always_inline }, closeFile, .{
                        @ptrCast(*Self, @alignCast(alignment, ptr)),
                        file,
                    });
                }
            };

            break :blk .{
                .cwdFn = gen.cwdEntry,
                .openFileFromDirFn = gen.openFileFromDirEntry,
                .closeFileFn = gen.closeEntry,
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
