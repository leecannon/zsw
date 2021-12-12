const std = @import("std");

const impl = @import("impl.zig");
const interface = @import("interface.zig");
const types = @import("types.zig");

pub const Config = impl.Config;
pub const Backend = impl.Backend;
pub const Sys = interface.Sys;

pub const Dir = types.Dir;
pub const File = types.File;

test {
    var backend = Backend(null){};
    const sys = backend.sys();

    const cwd = sys.cwd();

    const file = try cwd.openFile("LICENSE", .{});
    defer file.close();
}

comptime {
    std.testing.refAllDecls(@This());
}
