const std = @import("std");

pub const FileSystemDescription = struct {
    allocator: std.mem.Allocator,

    /// Do not modify directly
    entries: std.ArrayListUnmanaged(*EntryDescription) = .{},

    /// Do not modify directly
    root: *EntryDescription,

    /// Do not modify directly
    _cwd: *EntryDescription,

    pub fn init(allocator: std.mem.Allocator) !*FileSystemDescription {
        var fs_desc = try allocator.create(FileSystemDescription);
        errdefer allocator.destroy(fs_desc);

        const root_name = try allocator.dupe(u8, "root");
        errdefer allocator.free(root_name);

        var root_dir = try allocator.create(EntryDescription);
        errdefer allocator.destroy(root_dir);

        root_dir.* = .{
            .file_system_description = fs_desc,
            .name = root_name,
            .subdata = .{ .dir = .{} },
        };

        fs_desc.* = .{
            .allocator = allocator,
            .root = root_dir,
            ._cwd = root_dir,
        };

        try fs_desc.entries.append(allocator, root_dir);

        return fs_desc;
    }

    pub fn deinit(self: *FileSystemDescription) void {
        for (self.entries.items) |entry| entry.deinit();
        self.entries.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn cwd(self: *const FileSystemDescription) *EntryDescription {
        return self._cwd;
    }

    pub fn setCwd(self: *FileSystemDescription, entry: *EntryDescription) void {
        std.debug.assert(entry.subdata == .dir);
        self._cwd = entry;
    }

    pub const EntryDescription = struct {
        file_system_description: *FileSystemDescription,

        name: []const u8,

        subdata: SubData,

        pub const SubData = union(enum) {
            file: FileData,
            dir: DirData,

            pub const FileData = struct {
                contents: []const u8,
            };

            pub const DirData = struct {
                entries: std.ArrayListUnmanaged(*EntryDescription) = .{},
            };

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        pub fn addFile(self: *EntryDescription, name: []const u8, content: []const u8) !void {
            std.debug.assert(self.subdata == .dir);
            const allocator = self.file_system_description.allocator;

            const duped_name = try allocator.dupe(u8, name);
            errdefer allocator.free(duped_name);

            const duped_content = try allocator.dupe(u8, content);
            errdefer allocator.free(duped_content);

            var file = try allocator.create(EntryDescription);
            errdefer allocator.destroy(file);

            file.* = .{
                .file_system_description = self.file_system_description,
                .name = duped_name,
                .subdata = .{ .file = .{ .contents = duped_content } },
            };

            try self.subdata.dir.entries.append(allocator, file);
            errdefer _ = self.subdata.dir.entries.pop();

            try self.file_system_description.entries.append(allocator, file);
        }

        pub fn addDirectory(self: *EntryDescription, name: []const u8) !*EntryDescription {
            std.debug.assert(self.subdata == .dir);
            const allocator = self.file_system_description.allocator;

            const duped_name = try allocator.dupe(u8, name);
            errdefer allocator.free(duped_name);

            var dir = try allocator.create(EntryDescription);
            errdefer allocator.destroy(dir);

            dir.* = .{
                .file_system_description = self.file_system_description,
                .name = duped_name,
                .subdata = .{ .dir = .{} },
            };

            try self.subdata.dir.entries.append(allocator, dir);
            errdefer _ = self.subdata.dir.entries.pop();

            try self.file_system_description.entries.append(allocator, dir);

            return dir;
        }

        fn deinit(self: *EntryDescription) void {
            const allocator = self.file_system_description.allocator;

            allocator.free(self.name);

            switch (self.subdata) {
                .file => |file| allocator.free(file.contents),
                .dir => |*dir| dir.entries.deinit(allocator),
            }

            allocator.destroy(self);
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
