const std = @import("std");

/// A pointer to the source to be used as the current time in nanoseconds.
/// Reads are atomic with Acquire ordering.
///
/// Note: This pointer must be valid for as long as the `Backend` exists.
nano_timestamp: *const i128,

comptime {
    std.testing.refAllDecls(@This());
}
