const zsw = @import("src/main.zig");

pub fn main() !void {
    var backend = zsw.Backend(null){};
    const sys = backend.sys();

    const cwd = sys.cwd();

    const f = try cwd.openFile("LICENSE", .{});
    _ = f;
}
