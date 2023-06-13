const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const examples = try getExamples(b.allocator);

    addTests(b, optimize, examples);
    try createExamples(b, optimize, target, examples);
}

fn createExamples(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget, examples: []const Example) !void {
    for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = .{ .path = example.path },
            .target = target,
            .optimize = optimize,
        });
        example_exe.addAnonymousModule("zsw", .{ .source_file = .{ .path = "src/main.zig" } });

        const run = b.addRunArtifact(example_exe);

        const desc = try std.fmt.allocPrint(b.allocator, "run example '{s}' from '{s}' section", .{ example.name, example.section });

        const example_step = b.step(example.name, desc);
        example_step.dependOn(&run.step);
    }
}

fn addTests(b: *std.Build, optimize: std.builtin.OptimizeMode, examples: []const Example) void {
    const test_step = b.step("test", "Run all tests");

    const lib_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    for (examples) |example| {
        const example_test = b.addTest(.{
            .root_source_file = .{ .path = example.path },
            .optimize = optimize,
        });
        example_test.addAnonymousModule("zsw", .{ .source_file = .{ .path = "src/main.zig" } });
        const run_example_test = b.addRunArtifact(example_test);
        test_step.dependOn(&run_example_test.step);
    }

    b.default_step = test_step;
}

const Example = struct {
    section: []const u8,
    name: []const u8,
    path: []const u8,

    pub fn deinit(self: Example, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

const CURRENT_FOLDER = getFileFolder();

fn getFileFolder() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

fn getExamples(allocator: std.mem.Allocator) ![]const Example {
    var examples = std.ArrayList(Example).init(allocator);
    errdefer {
        for (examples.items) |s| s.deinit(allocator);
        examples.deinit();
    }

    var build_dir = try std.fs.cwd().openDir(getFileFolder(), .{});
    defer build_dir.close();

    var example_dir = try build_dir.openDir("examples", .{});
    defer example_dir.close();

    const example_sections: []const []const u8 = &.{"file_system"};

    inline for (example_sections) |example_section| {
        var examples_dir = try example_dir.openIterableDir(example_section, .{});
        defer examples_dir.close();

        var iter = examples_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            const path = try std.fmt.allocPrint(allocator, CURRENT_FOLDER ++ "/examples/" ++ example_section ++ "/{s}", .{entry.name});
            errdefer allocator.free(path);

            const extension = std.fs.path.extension(path);
            const name = path[(path.len - entry.name.len)..(path.len - extension.len)];

            try examples.append(.{
                .section = example_section,
                .name = name,
                .path = path,
            });
        }
    }

    return examples.toOwnedSlice();
}
