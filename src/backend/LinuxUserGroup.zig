const std = @import("std");

const Config = @import("../Config.zig").Config;

pub fn LinuxUserGroup(comptime config: Config) type {
    if (!config.linux_user_group) return struct {};

    return struct {
        euid: std.os.uid_t,

        const Self = @This();
        const log = std.log.scoped(config.logging_scope);

        pub fn osLinuxGeteuid(self: *Self) std.os.uid_t {
            if (config.log) {
                log.info("osLinuxGeteuid called, returning {}", .{self.euid});
            }

            return self.euid;
        }
    };
}

comptime {
    @import("../Config.zig").referenceAllIterations(LinuxUserGroup);
}

comptime {
    std.testing.refAllDecls(@This());
}
