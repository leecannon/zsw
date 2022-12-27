const std = @import("std");

const System = @import("../interface/System.zig");
const Dir = @import("../interface/Dir.zig");
const File = @import("../interface/File.zig");

const Config = @import("../config/Config.zig");
const FileSystemDescription = @import("../config/FileSystemDescription.zig");
const LinuxUserGroupDescription = @import("../config/LinuxUserGroupDescription.zig");
const TimeDescription = @import("../config/TimeDescription.zig");

const FileSystem = @import("FileSystem.zig").FileSystem;
const LinuxUserGroup = @import("LinuxUserGroup.zig").LinuxUserGroup;
const Time = @import("Time.zig").Time;

const host_backend = @import("host_backend.zig");

pub fn Backend(comptime config: Config) type {
    return struct {
        allocator: std.mem.Allocator,
        file_system: FileSystem(config),
        linux_user_group: LinuxUserGroup(config),
        time: Time(config),

        const log = std.log.scoped(config.logging_scope);

        const Self = @This();

        /// For information regarding the `description` argument see `Config`
        pub fn init(allocator: std.mem.Allocator, description: anytype) !*Self {
            var self: *Self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;

            const DescriptionType = @TypeOf(description);

            // time must be set before `file_system` as `FileSystem.init` needs to know times
            if (config.time) {
                comptime {
                    const err = "time capability requested without `time` field in `description` with type `TimeDescription`";
                    if (!@hasField(DescriptionType, "time")) {
                        @compileError(err);
                    }
                    if (@TypeOf(description.time) != *TimeDescription and
                        @TypeOf(description.time) != *const TimeDescription)
                    {
                        @compileError(err);
                    }
                }

                const time_desc: *const TimeDescription = &description.time;

                self.time = .{
                    .nano_timestamp = time_desc.nano_timestamp,
                };
            }

            if (config.file_system) {
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

                self.file_system = try FileSystem(config).init(allocator, self.system(), description.file_system);
            }

            if (config.linux_user_group) {
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

                self.linux_user_group = .{
                    .euid = linux_user_group_desc.initial_euid,
                };
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            if (config.file_system) {
                self.file_system.deinit();
            }
            self.allocator.destroy(self);
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

        fn nanoTimestamp(interface: System) i128 {
            if (!config.time) {
                if (config.fallback_to_host) {
                    return host_backend.nanoTimestamp(interface);
                }
                @panic("nanoTimestamp requires time capability");
            }

            return getSelf(interface).time.nanoTimestamp();
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

        fn createFileFromDir(interface: System, dir: Dir, sub_path: []const u8, flags: File.CreateFlags) File.OpenError!File {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.createFileFromDir(interface, dir, sub_path, flags);
                }
                @panic("createFileFromDir required file_system capability");
            }

            return File{
                .system = interface,
                .data = .{ .custom = try getSelf(interface).file_system.createFileFromDir(dir.data.custom, sub_path, flags) },
            };
        }

        fn statDir(interface: System, dir: Dir) File.StatError!File.Stat {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.statDir(interface, dir);
                }
                @panic("statDir requires file_system capability");
            }

            return getSelf(interface).file_system.stat(dir.data.custom);
        }

        pub fn updateTimesDir(interface: System, dir: Dir, atime: i128, mtime: i128) File.UpdateTimesError!void {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.updateTimesDir(interface, dir, atime, mtime);
                }
                @panic("updateTimesDir requires file_system capability");
            }

            return getSelf(interface).file_system.updateTimes(dir.data.custom, atime, mtime);
        }

        fn readFile(interface: System, file: File, buffer: []u8) std.os.ReadError!usize {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.readFile(interface, file, buffer);
                }
                @panic("readFile requires file_system capability");
            }

            return getSelf(interface).file_system.readFile(file.data.custom, buffer);
        }

        fn statFile(interface: System, file: File) File.StatError!File.Stat {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.statFile(interface, file);
                }
                @panic("statFile requires file_system capability");
            }

            return getSelf(interface).file_system.stat(file.data.custom);
        }

        pub fn updateTimesFile(interface: System, file: File, atime: i128, mtime: i128) File.UpdateTimesError!void {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.updateTimesFile(interface, file, atime, mtime);
                }
                @panic("updateTimesFile requires file_system capability");
            }

            return getSelf(interface).file_system.updateTimes(file.data.custom, atime, mtime);
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

        const vtable: System.VTable = .{
            .cwd = cwd,
            .nanoTimestamp = nanoTimestamp,
            .osLinuxGeteuid = osLinuxGeteuid,
            .openFileFromDir = openFileFromDir,
            .createFileFromDir = createFileFromDir,
            .statDir = statDir,
            .updateTimesDir = updateTimesDir,
            .readFile = readFile,
            .statFile = statFile,
            .updateTimesFile = updateTimesFile,
            .closeFile = closeFile,
        };

        inline fn getSelf(interface: System) *Self {
            return @ptrCast(*Self, @alignCast(@alignOf(Self), interface.ptr));
        }

        comptime {
            @import("../internal.zig").referenceAllIterations(Backend);
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };
}

comptime {
    std.testing.refAllDecls(@This());
}
