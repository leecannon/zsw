const std = @import("std");

const System = @import("../interface/System.zig");
const Dir = @import("../interface/Dir.zig");
const File = @import("../interface/File.zig");
const Uname = @import("../interface/Uname.zig").Uname;

const Config = @import("../config/Config.zig");
const FileSystemDescription = @import("../config/FileSystemDescription.zig");
const LinuxUserGroupDescription = @import("../config/LinuxUserGroupDescription.zig");
const TimeDescription = @import("../config/TimeDescription.zig");
const UnameDescription = @import("../config/UnameDescription.zig");

const FileSystemBackend = @import("FileSystemBackend.zig").FileSystemBackend;
const LinuxUserGroupBackend = @import("LinuxUserGroupBackend.zig").LinuxUserGroupBackend;
const TimeBackend = @import("TimeBackend.zig").TimeBackend;
const UnameBackend = @import("UnameBackend.zig").UnameBackend;

const host_backend = @import("host_backend.zig");

pub fn Backend(comptime config: Config) type {
    return struct {
        allocator: std.mem.Allocator,
        file_system: FileSystemBackend(config),
        linux_user_group: LinuxUserGroupBackend(config),
        time: TimeBackend(config),
        uname_backend: UnameBackend(config),

        const log = std.log.scoped(config.logging_scope);

        const Self = @This();

        /// For information regarding the `description` argument see `Config`
        pub fn create(allocator: std.mem.Allocator, description: anytype) !*Self {
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
                    if (@TypeOf(description.time) != TimeDescription) {
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

                self.file_system = try FileSystemBackend(config).create(allocator, self.system(), description.file_system);
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

            if (config.uname) {
                comptime {
                    const err = "uanme capability requested without `uname` field in `description` with type `UnameDescription`";
                    if (!@hasField(DescriptionType, "uname")) {
                        @compileError(err);
                    }
                    if (@TypeOf(description.uname) != UnameDescription) {
                        @compileError(err);
                    }
                }

                const uname_desc: *const UnameDescription = &description.uname;

                const operating_system_name = try allocator.dupe(u8, uname_desc.operating_system_name);
                errdefer allocator.free(operating_system_name);
                const host_name = try allocator.dupe(u8, uname_desc.host_name);
                errdefer allocator.free(host_name);
                const release = try allocator.dupe(u8, uname_desc.release);
                errdefer allocator.free(release);
                const version = try allocator.dupe(u8, uname_desc.version);
                errdefer allocator.free(version);
                const hardware_identifier = try allocator.dupe(u8, uname_desc.hardware_identifier);
                errdefer allocator.free(hardware_identifier);
                const domain_name = try allocator.dupe(u8, uname_desc.domain_name);

                self.uname_backend = .{
                    .allocator = allocator,
                    .operating_system_name = operating_system_name,
                    .host_name = host_name,
                    .release = release,
                    .version = version,
                    .hardware_identifier = hardware_identifier,
                    .domain_name = domain_name,
                };
            }

            return self;
        }

        pub fn destroy(self: *Self) void {
            if (config.file_system) {
                self.file_system.destroy();
            }
            self.allocator.destroy(self);
        }

        pub inline fn system(self: *Self) System {
            return .{
                ._ptr = self,
                ._vtable = &vtable,
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
                ._system = interface,
                ._data = .{ .custom = getSelf(interface).file_system.cwd() },
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

        fn uname(interface: System) Uname {
            if (!config.uname) {
                if (config.fallback_to_host) {
                    return host_backend.uname(interface);
                }
                @panic("uname requires uname capability");
            }

            return getSelf(interface).uname_backend.uname();
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

        fn getStdIn(interface: System) File {
            _ = interface;
            @panic("stdio is not implemented in the custom backend");
        }

        fn getStdErr(interface: System) File {
            _ = interface;
            @panic("stdio is not implemented in the custom backend");
        }

        fn getStdOut(interface: System) File {
            _ = interface;
            @panic("stdio is not implemented in the custom backend");
        }

        fn openFileFromDir(
            interface: System,
            dir: Dir,
            sub_path: []const u8,
            flags: File.OpenFlags,
        ) File.OpenError!File {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.openFileFromDir(interface, dir, sub_path, flags);
                }
                @panic("openFileFromDir requires file_system capability");
            }

            return .{
                ._system = interface,
                ._data = .{
                    .custom = try getSelf(interface).file_system.openFileFromDir(
                        dir._data.custom,
                        sub_path,
                        flags,
                    ),
                },
            };
        }

        fn createFileFromDir(
            interface: System,
            dir: Dir,
            sub_path: []const u8,
            flags: File.CreateFlags,
        ) File.OpenError!File {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.createFileFromDir(interface, dir, sub_path, flags);
                }
                @panic("createFileFromDir required file_system capability");
            }

            return .{
                ._system = interface,
                ._data = .{
                    .custom = try getSelf(interface).file_system.createFileFromDir(
                        dir._data.custom,
                        sub_path,
                        flags,
                    ),
                },
            };
        }

        fn statDir(interface: System, dir: Dir) File.StatError!File.Stat {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.statDir(interface, dir);
                }
                @panic("statDir requires file_system capability");
            }

            return getSelf(interface).file_system.stat(dir._data.custom);
        }

        fn updateTimesDir(
            interface: System,
            dir: Dir,
            atime: i128,
            mtime: i128,
        ) File.UpdateTimesError!void {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.updateTimesDir(interface, dir, atime, mtime);
                }
                @panic("updateTimesDir requires file_system capability");
            }

            return getSelf(interface).file_system.updateTimes(dir._data.custom, atime, mtime);
        }

        fn readFile(interface: System, file: File, buffer: []u8) std.os.ReadError!usize {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.readFile(interface, file, buffer);
                }
                @panic("readFile requires file_system capability");
            }

            return getSelf(interface).file_system.readFile(file._data.custom, buffer);
        }

        fn statFile(interface: System, file: File) File.StatError!File.Stat {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.statFile(interface, file);
                }
                @panic("statFile requires file_system capability");
            }

            return getSelf(interface).file_system.stat(file._data.custom);
        }

        fn updateTimesFile(
            interface: System,
            file: File,
            atime: i128,
            mtime: i128,
        ) File.UpdateTimesError!void {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.updateTimesFile(interface, file, atime, mtime);
                }
                @panic("updateTimesFile requires file_system capability");
            }

            return getSelf(interface).file_system.updateTimes(file._data.custom, atime, mtime);
        }

        fn closeFile(interface: System, file: File) void {
            if (!config.file_system) {
                if (config.fallback_to_host) {
                    return host_backend.closeFile(interface, file);
                }
                @panic("closeFile requires file_system capability");
            }

            getSelf(interface).file_system.closeFile(file._data.custom);
        }

        const vtable: System.VTable = .{
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
        };

        inline fn getSelf(interface: System) *Self {
            return @as(*Self, @ptrCast(@alignCast(interface._ptr)));
        }

        comptime {
            @import("../internal.zig").referenceAllIterations(Backend);
        }
    };
}

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
