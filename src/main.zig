const std = @import("std");

const backend = @import("backend.zig");
const interface = @import("interface.zig");
const types = @import("types.zig");

pub const Config = backend.Config;
pub const CustomBackend = backend.CustomBackend;

/// This backend uses the host system directly 
pub const host_system = backend.HostBackend.system;

pub const System = interface.System;

pub const Dir = types.Dir;
pub const File = types.File;

comptime {
    std.testing.refAllDecls(@This());
}
