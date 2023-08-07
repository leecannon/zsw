const std = @import("std");
const FileSystemDescription = @This();

allocator: std.mem.Allocator,

/// This is only used to keep hold of all the created entries for them to be freed.
entries: std.ArrayListUnmanaged(*EntryDescription) = .{},

/// Do not assign directly.
root: *EntryDescription,

/// Do not assign directly.
cwd: *EntryDescription,

/// Create a new file system description containing only a single entry description of a directory which is set
/// as the root entry and current working directory.
pub fn create(allocator: std.mem.Allocator) !*FileSystemDescription {
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
        .cwd = root_dir,
    };

    try fs_desc.entries.append(allocator, root_dir);

    return fs_desc;
}

pub fn destroy(self: *FileSystemDescription) void {
    for (self.entries.items) |entry| entry.deinit();
    self.entries.deinit(self.allocator);
    self.allocator.destroy(self);
}

/// Get the current working directory.
pub fn getCwd(self: *const FileSystemDescription) *EntryDescription {
    return self.cwd;
}

/// Set the current working directory.
/// `entry` must be a directory.
pub fn setCwd(self: *FileSystemDescription, entry: *EntryDescription) void {
    std.debug.assert(entry.subdata == .dir); // cwd must be a directory
    self.cwd = entry;
}

/// Describes an entry in the file system description.
/// Either a file or a directory.
pub const EntryDescription = struct {
    file_system_description: *FileSystemDescription,

    name: []const u8,

    /// time of last access, if null is set to current time at construction
    atime: ?i128 = null,
    /// time of last modification, if null is set to current time at construction
    mtime: ?i128 = null,
    /// time of last status change, if null is set to current time at construction
    ctime: ?i128 = null,

    /// contains data specific to different entry types
    subdata: SubData,

    pub const SubData = union(enum) {
        file: FileData,
        dir: DirData,

        pub const FileData = struct {
            contents: []const u8,
        };

        pub const DirData = struct {
            entries: std.StringArrayHashMapUnmanaged(*EntryDescription) = .{},
        };
    };

    /// Add a file entry description to this directory entry description.
    /// `self` must be a directory entry description.
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

        const result = try self.subdata.dir.entries.getOrPut(allocator, duped_name);
        if (result.found_existing) return error.DuplicateEntryName;

        result.value_ptr.* = file;
        errdefer _ = self.subdata.dir.entries.pop();

        try self.file_system_description.entries.append(allocator, file);
    }

    /// Add a directory entry description to this directory entry description.
    /// `self` must be a directory entry description.
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

        const result = try self.subdata.dir.entries.getOrPut(allocator, duped_name);
        if (result.found_existing) return error.DuplicateEntryName;

        result.value_ptr.* = dir;
        errdefer _ = self.subdata.dir.entries.pop();

        try self.file_system_description.entries.append(allocator, dir);

        return dir;
    }

    fn deinit(self: *EntryDescription) void {
        const allocator = self.file_system_description.allocator;

        switch (self.subdata) {
            .file => |file| allocator.free(file.contents),
            .dir => |*dir| dir.entries.deinit(allocator),
        }

        allocator.free(self.name);

        allocator.destroy(self);
    }
};

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .Struct, .Enum, .Union, .Opaque => {
                    refAllDeclsRecursive(@field(T, decl.name));
                    _ = @field(T, decl.name);
                },
                .Type, .Fn => {
                    _ = @field(T, decl.name);
                },
                else => {},
            }
        }
    }
}
