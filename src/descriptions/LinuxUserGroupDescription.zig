const std = @import("std");

pub const LinuxUserGroupDescription = struct {
    initial_euid: std.os.uid_t,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
