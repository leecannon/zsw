const std = @import("std");

// ** CONFIGURATION

pub const Config = @import("config/Config.zig");
pub const FileSystemDescription = @import("config/FileSystemDescription.zig");
pub const LinuxUserGroupDescription = @import("config/LinuxUserGroupDescription.zig");
pub const TimeDescription = @import("config/TimeDescription.zig");

// ** CUSTOM BACKEND

const backend = @import("backend/Backend.zig");
pub const Backend = backend.Backend;

// ** SYSTEM BACKEND

/// This system calls the host directly
pub const host_system: System = host_backend.host_system;
const host_backend = @import("backend/host_backend.zig");

// ** INTERFACE

pub const System = @import("interface/System.zig");
pub const Dir = @import("interface/Dir.zig");
pub const File = @import("interface/File.zig");

comptime {
    std.testing.refAllDecls(@This());
}
