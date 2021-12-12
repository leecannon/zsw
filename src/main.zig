const std = @import("std");

const backend = @import("backend.zig");
const interface = @import("interface.zig");
const types = @import("types.zig");

pub const Config = backend.Config;
pub const Backend = backend.Backend;

/// This backend uses the host system directly 
pub const HostBackend = Backend(null);

pub const System = interface.System;

pub const Dir = types.Dir;
pub const File = types.File;

test {
    var back = HostBackend{};
    const sys = back.system();

    const cwd = sys.cwd();

    const file = try cwd.openFile("LICENSE", .{});
    defer file.close();
}

comptime {
    std.testing.refAllDecls(@This());
}
