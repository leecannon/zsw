const std = @import("std");

const System = @import("../interface/System.zig").System;
const Dir = @import("../interface/Dir.zig").Dir;
const File = @import("../interface/File.zig").File;

const Config = @import("../Config.zig").Config;
const FileSystemDescription = @import("../descriptions/FileSystemDescription.zig").FileSystemDescription;
const LinuxUserGroupDescription = @import("../descriptions/LinuxUserGroupDescription.zig").LinuxUserGroupDescription;

const FileSystem = @import("FileSystem.zig").FileSystem;
const LinuxUserGroup = @import("LinuxUserGroup.zig").LinuxUserGroup;

const host_backend = @import("host_backend.zig");

pub fn Backend(comptime config: Config) type {
    return struct {
        allocator: std.mem.Allocator,
        file_system: FileSystem(config),
        linux_user_group: LinuxUserGroup(config),

        const log = std.log.scoped(config.logging_scope);

        const Self = @This();

        /// For information regarding the `description` argument see `Config`
        pub fn init(allocator: std.mem.Allocator, description: anytype) !Self {
            log.info("\n\n{}\n\n", .{description});

            const DescriptionType = @TypeOf(description);

            const file_system: FileSystem(config) = if (config.file_system) blk: {
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
            } else .{};

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

        pub inline fn getSystem(self: *Self) System {
            return .{
                .ptr = self,
                .vtable = &vtable,
            };
        }

        fn cwd(system: System) Dir {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.cwd(system);
                }
                @panic("cwd requires file_system capability");
            }

            return .{
                .system = system,
                .data = .{ .custom = getSelf(system).file_system.cwd() },
            };
        }

        fn openFileFromDir(system: System, dir: Dir, sub_path: []const u8, flags: File.OpenFlags) File.OpenError!File {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.openFileFromDir(system, dir, sub_path, flags);
                }
                @panic("openFileFromDir requires file_system capability");
            }

            return File{
                .system = system,
                .data = .{ .custom = try getSelf(system).file_system.openFileFromDir(dir.data.custom, sub_path, flags) },
            };
        }

        fn readFile(system: System, file: File, buffer: []u8) std.os.ReadError!usize {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.readFile(system, file, buffer);
                }
                @panic("readFile requires file_system capability");
            }

            return try getSelf(system).file_system.readFile(file.data.custom, buffer);
        }

        fn closeFile(system: System, file: File) void {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.closeFile(system, file);
                }
                @panic("closeFile requires file_system capability");
            }

            getSelf(system).file_system.closeFile(file.data.custom);
        }

        fn osLinuxGeteuid(system: System) std.os.uid_t {
            if (!config.linux_user_group) {
                if (config.fallback_to_host) {
                    return host_backend.osLinuxGeteuid(system);
                }
                @panic("osLinuxGeteuid requires file_system capability");
            }

            return getSelf(system).linux_user_group.osLinuxGeteuid();
        }

        const vtable: System.VTable = .{
            .cwd = cwd,
            .openFileFromDir = openFileFromDir,
            .readFile = readFile,
            .closeFile = closeFile,
            .osLinuxGeteuid = osLinuxGeteuid,
        };

        inline fn getSelf(system: System) *Self {
            return @ptrCast(*Self, @alignCast(@alignOf(Self), system.ptr));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };
}

comptime {
    std.testing.refAllDecls(@This());
}
