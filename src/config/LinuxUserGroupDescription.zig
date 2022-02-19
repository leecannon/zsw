const std = @import("std");

initial_euid: std.os.uid_t,

comptime {
    std.testing.refAllDecls(@This());
}
