const std = @import("std");

const System = @import("../interface/System.zig").System;
const Dir = @import("../interface/Dir.zig").Dir;
const File = @import("../interface/File.zig").File;

const Config = @import("../config/Config.zig").Config;
const FileSystemDescription = @import("../config/FileSystemDescription.zig").FileSystemDescription;
const LinuxUserGroupDescription = @import("../config/LinuxUserGroupDescription.zig").LinuxUserGroupDescription;

const FileSystem = @import("FileSystem.zig").FileSystem;
const LinuxUserGroup = @import("LinuxUserGroup.zig").LinuxUserGroup;

const host_backend = @import("host_backend.zig");

pub fn Backend(comptime config: Config) type {
    return struct {
        allocator: std.mem.Allocator,
        file_system: *FileSystem(config),
        linux_user_group: LinuxUserGroup(config),

        const log = std.log.scoped(config.logging_scope);

        const Self = @This();

        /// For information regarding the `description` argument see `Config`
        pub fn init(allocator: std.mem.Allocator, description: anytype) !Self {
            const DescriptionType = @TypeOf(description);

            const file_system: *FileSystem(config) = if (config.file_system) blk: {
                comptime {
                    const err = "file system capability requested without `file_system` field in `description` with type `FileSystemDescription`";
                    if (!@hasField(DescriptionType, "file_system")) {
                        @compileError(err);
                    }
                    if (@TypeOf(description.file_system) != *FileSystemDescription and
                        @TypeOf(description.file_system) != *const FileSystemDescription)
                    {
                        @compileError(err);
                    }
                }

                break :blk try FileSystem(config).init(allocator, description.file_system);
            } else undefined;

            const linux_user_group: LinuxUserGroup(config) = if (config.linux_user_group) blk: {
                comptime {
                    const err = "linux user group capability requested without `linux_user_group` field in `description` with type `LinuxUserGroupDescription`";
                    if (!@hasField(DescriptionType, "linux_user_group")) {
                        @compileError(err);
                    }
                    if (@TypeOf(description.linux_user_group) != LinuxUserGroupDescription) {
                        @compileError(err);
                    }
                }

                const linux_user_group_desc: *const LinuxUserGroupDescription = &description.linux_user_group;
                log.info("\n\n{}\n\n", .{linux_user_group_desc});

                break :blk LinuxUserGroup(config){
                    .euid = linux_user_group_desc.initial_euid,
                };
            } else .{};

            return Self{
                .allocator = allocator,
                .file_system = file_system,
                .linux_user_group = linux_user_group,
            };
        }

        pub fn deinit(self: *Self) void {
            if (config.file_system) {
                self.file_system.deinit();
            }
            self.* = undefined;
        }

        pub inline fn system(self: *Self) System {
            return .{
                .ptr = self,
                .vtable = &vtable,
            };
        }

        fn cwd(interface: System) Dir {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.cwd(interface);
                }
                @panic("cwd requires file_system capability");
            }

            return .{
                .system = interface,
                .data = .{ .custom = getSelf(interface).file_system.cwd() },
            };
        }

        fn openFileFromDir(interface: System, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.openFileFromDir(interface, dir, sub_path, flags);
                }
                @panic("openFileFromDir requires file_system capability");
            }

            return File{
                .system = interface,
                .data = .{ .custom = try getSelf(interface).file_system.openFileFromDir(dir.data.custom, sub_path, flags) },
            };
        }

        fn readFile(interface: System, file: File, buffer: []u8) std.os.ReadError!usize {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.readFile(interface, file, buffer);
                }
                @panic("readFile requires file_system capability");
            }

            return try getSelf(interface).file_system.readFile(file.data.custom, buffer);
        }

        fn closeFile(interface: System, file: File) void {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.closeFile(interface, file);
                }
                @panic("closeFile requires file_system capability");
            }

            getSelf(interface).file_system.closeFile(file.data.custom);
        }

        fn osLinuxGeteuid(interface: System) std.os.uid_t {
            if (!config.linux_user_group) {
                if (config.fallback_to_host) {
                    return host_backend.osLinuxGeteuid(interface);
                }
                @panic("osLinuxGeteuid requires file_system capability");
            }

            return getSelf(interface).linux_user_group.osLinuxGeteuid();
        }

        const vtable: System.VTable = .{
            .cwd = cwd,
            .openFileFromDir = openFileFromDir,
            .readFile = readFile,
            .closeFile = closeFile,
            .osLinuxGeteuid = osLinuxGeteuid,
        };

        inline fn getSelf(interface: System) *Self {
            return @ptrCast(*Self, @alignCast(@alignOf(Self), interface.ptr));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };
}

comptime {
    @import("../config/Config.zig").referenceAllIterations(Backend);
}

comptime {
    std.testing.refAllDecls(@This());
}
