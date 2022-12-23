const std = @import("std");

const zsw = @import("zsw");
const BackendType = zsw.Backend(.{ .file_system = true, .log = true });

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var backend = try createBackend(allocator);
    defer backend.deinit();

    try use_system(allocator, backend.system());
}

fn use_system(allocator: std.mem.Allocator, system: zsw.System) !void {
    const cwd = system.cwd();

    const file_in_sub_dir = try cwd.openFile("file_in_sub_dir", .{});
    defer file_in_sub_dir.close();

    const file_in_sub_dir_contents = try file_in_sub_dir.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_in_sub_dir_contents);

    std.log.info("{s}", .{file_in_sub_dir_contents});

    const file_in_parent = try cwd.openFile("../file_in_root", .{});
    defer file_in_parent.close();

    const file_in_parent_contents = try file_in_parent.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_in_parent_contents);

    std.log.info("{s}", .{file_in_parent_contents});

    const file_in_parent_stat = try file_in_parent.stat();

    std.log.info("{}", .{file_in_parent_stat});
}

fn createBackend(allocator: std.mem.Allocator) !*BackendType {
    var file_system = try zsw.FileSystemDescription.init(allocator);
    defer file_system.deinit();

    try file_system.root.addFile("file_in_root", "this is the contents of file in root");

    const dir_in_root = try file_system.root.addDirectory("dir_in_root");
    try dir_in_root.addFile("file_in_sub_dir", "contents of file in sub dir");

    file_system.setCwd(dir_in_root);

    return try BackendType.init(allocator, .{ .file_system = file_system });
}

comptime {
    std.testing.refAllDecls(@This());
}
