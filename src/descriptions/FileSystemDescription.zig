const std = @import("std");

// TODO: It would be very nice if there was a way to do this without an allocator; preferably at comptime

pub const FileSystemDescription = struct {
    allocator: std.mem.Allocator,

    /// Do not modify directly
    entries: std.ArrayListUnmanaged(EntryDescription) = .{},
    starting_cwd: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !*FileSystemDescription {
        var fs_desc = try allocator.create(FileSystemDescription);
        errdefer allocator.destroy(fs_desc);

        fs_desc.* = .{
            .allocator = allocator,
        };

        const root_name = try allocator.dupe(u8, "root");
        errdefer allocator.free(root_name);

        var root_dir = try fs_desc.entries.addOne(allocator);

        root_dir.* = .{
            .name = root_name,
            .subdata = .{ .dir = .{} },
        };

        return fs_desc;
    }

    pub fn deinit(self: *FileSystemDescription) void {
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn getRoot(self: *const FileSystemDescription) u32 {
        _ = self;
        return 0;
    }

    pub fn getCwd(self: *const FileSystemDescription) u32 {
        return self.starting_cwd;
    }

    pub fn setCwd(self: *FileSystemDescription, index: u32) void {
        std.debug.assert(self.entries.items[index].subdata == .dir);
        self.starting_cwd = index;
    }

    pub fn addDirectory(self: *FileSystemDescription, parent_index: u32, name: []const u8) !u32 {
        const parent: *EntryDescription = &self.entries.items[parent_index];
        std.debug.assert(parent.subdata == .dir);

        const index = @intCast(u32, self.entries.items.len);

        const duped_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(duped_name);

        try parent.subdata.dir.entries.append(self.allocator, index);
        errdefer _ = parent.subdata.dir.entries.pop();

        var dir = try self.entries.addOne(self.allocator);

        dir.* = .{
            .name = duped_name,
            .subdata = .{ .dir = .{} },
        };

        return index;
    }

    pub fn addFile(self: *FileSystemDescription, parent_index: u32, name: []const u8, content: []const u8) !void {
        const parent: *EntryDescription = &self.entries.items[parent_index];
        std.debug.assert(parent.subdata == .dir);

        const duped_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(duped_name);

        const duped_content = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(duped_content);

        try parent.subdata.dir.entries.append(self.allocator, @intCast(u32, self.entries.items.len));
        errdefer _ = parent.subdata.dir.entries.pop();

        var file = try self.entries.addOne(self.allocator);

        file.* = .{
            .name = duped_name,
            .subdata = .{ .file = .{ .contents = duped_content } },
        };
    }

    pub const EntryDescription = struct {
        name: []const u8,

        subdata: SubData,

        pub const SubData = union(enum) {
            file: FileData,
            dir: DirData,

            pub const FileData = struct {
                contents: []const u8,
            };

            pub const DirData = struct {
                entries: std.ArrayListUnmanaged(u32) = .{},
            };

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        pub fn deinit(self: *EntryDescription, allocator: std.mem.Allocator) void {
            allocator.free(self.name);

            switch (self.subdata) {
                .file => |file| allocator.free(file.contents),
                .dir => |*dir| dir.entries.deinit(allocator),
            }
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
