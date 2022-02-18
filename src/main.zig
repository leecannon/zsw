const std = @import("std");

// ** CONFIGURATION

pub const Config = @import("config/Config.zig").Config;
pub const FileSystemDescription = @import("config/FileSystemDescription.zig").FileSystemDescription;
pub const LinuxUserGroupDescription = @import("config/LinuxUserGroupDescription.zig").LinuxUserGroupDescription;

// ** CUSTOM BACKEND

pub const Backend = @import("backend/Backend.zig").Backend;

// ** SYSTEM BACKEND

/// This system calls the host directly
pub const host_system: System = host_backend.host_system;
const host_backend = @import("backend/host_backend.zig");

// ** INTERFACE

pub const System = @import("interface/System.zig").System;
pub const Dir = @import("interface/Dir.zig").Dir;
pub const File = @import("interface/File.zig").File;

comptime {
    std.testing.refAllDecls(@This());
}
