const std = @import("std");

/// The initial effective user id that backend should use.
initial_euid: std.os.uid_t,

comptime {
    std.testing.refAllDecls(@This());
}
