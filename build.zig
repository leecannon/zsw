const std = @import("std");

const pkg = std.build.Pkg{
    .name = "zsw",
    .path = .{ .path = "src/main.zig" },
};

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const examples = try getExamples(b.allocator);

    addTests(b, mode, examples);
    try createExamples(b, mode, target, examples);
}

fn createExamples(b: *std.build.Builder, mode: std.builtin.Mode, target: std.zig.CrossTarget, examples: []const Example) !void {
    for (examples) |example| {
        const example_exe = b.addExecutable(example.name, example.path);
        example_exe.setBuildMode(mode);
        example_exe.setTarget(target);
        example_exe.addPackage(pkg);

        const run = example_exe.run();

        const desc = try std.fmt.allocPrint(b.allocator, "run example '{s}'", .{example.name});

        const example_step = b.step(example.name, desc);
        example_step.dependOn(&run.step);
    }
}

fn addTests(b: *std.build.Builder, mode: std.builtin.Mode, examples: []const Example) void {
    const test_step = b.step("test", "Run all tests");

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);
    test_step.dependOn(&lib_tests.step);

    for (examples) |example| {
        const example_test = b.addTest(example.path);
        example_test.setBuildMode(mode);
        example_test.addPackage(pkg);
        test_step.dependOn(&example_test.step);
    }

    b.default_step = test_step;
}

const Example = struct {
    name: []const u8,
    path: []const u8,

    pub fn deinit(self: Example, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

const CURRENT_FOLDER = getFileFolder();

fn getFileFolder() []const u8 {
    return std.fs.path.dirname(@src().file) orelse @panic("root");
}

fn getExamples(allocator: std.mem.Allocator) ![]const Example {
    var examples = std.ArrayList(Example).init(allocator);
    errdefer {
        for (examples.items) |s| s.deinit(allocator);
        examples.deinit();
    }

    var examples_dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examples_dir.close();

    var iter = examples_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .File) continue;

        const path = try std.fmt.allocPrint(allocator, CURRENT_FOLDER ++ "/examples/{s}", .{entry.name});
        errdefer allocator.free(path);

        const extension = std.fs.path.extension(path);
        const name = path[(path.len - entry.name.len)..(path.len - extension.len)];

        try examples.append(.{
            .name = name,
            .path = path,
        });
    }

    return examples.toOwnedSlice();
}
