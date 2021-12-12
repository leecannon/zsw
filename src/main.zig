const std = @import("std");

pub const Config = struct {};

pub fn ZswImpl(comptime config: Config) type {
    _ = config;

    return struct {
        field: usize = 0,

        const Self = @This();
        const vtable: VTable = createVTable();

        pub fn zsw(self: *Self) Zsw {
            return .{
                .z_ptr = self,
                .z_vtable = &vtable,
            };
        }

        fn hello(self: *Self) void {
            _ = self;
            std.log.info("hello", .{});
        }

        fn createVTable() VTable {
            const alignment = @alignOf(Self);

            const gen = struct {
                fn helloImpl(ptr: *c_void) void {
                    const self = @ptrCast(*Self, @alignCast(alignment, ptr));
                    return @call(.{ .modifier = .always_inline }, hello, .{self});
                }
            };

            return .{
                .helloFn = gen.helloImpl,
            };
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };
}

const VTable = struct {
    helloFn: fn (ptr: *c_void) void,
};

pub const Zsw = struct {
    z_ptr: *c_void,
    z_vtable: *const VTable,

    pub fn hello(self: Zsw) void {
        self.z_vtable.helloFn(self.z_ptr);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

test {
    var impl = ZswImpl(.{}){};
    const zsw = impl.zsw();

    zsw.hello();
}

comptime {
    std.testing.refAllDecls(@This());
}
