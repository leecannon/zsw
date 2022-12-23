const std = @import("std");
const Config = @This();

/// Should the backend emit log messages
/// Messages are only logged for enabled capabilities
log: bool = false,

/// The `std.log` scope to use
logging_scope: @Type(.EnumLiteral) = .zsw,

/// If the requested capability is not enabled and this is `true` the request is forwarded
/// to the host, if this is `false` panic
fallback_to_host: bool = true,

/// Enable file system capability
///
/// If this capability is enabled the `arguments` parameter to `init` requires
/// a `file_system` field of type `*const FileSystemDescription`
file_system: bool = false,

/// Enable linux user and group capability
///
/// If this capability is enabled the `arguments` parameter to `init` requires
/// a `linux_user_group` field of type `LinuxUserGroupDescription`
linux_user_group: bool = false,

/// Enable time capability
///
/// If this capability is enabled the `arguments` parameter to `init` requires
/// a `time` field of type `TimeDescription`
time: bool = false,

// TODO: Actually implement this
thread_safe: bool = false,

comptime {
    std.testing.refAllDecls(@This());
}
