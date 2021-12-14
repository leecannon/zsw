const std = @import("std");

const System = @import("../interface/System.zig").System;
const Dir = @import("../interface/Dir.zig").Dir;
const File = @import("../interface/File.zig").File;

const Config = @import("../Config.zig").Config;
const FileSystemDescription = @import("../descriptions/FileSystemDescription.zig").FileSystemDescription;

pub fn FileSystem(comptime config: Config) type {
    if (!config.file_system) return struct {};

    return struct {
        allocator: std.mem.Allocator,

        entries: std.AutoHashMapUnmanaged(*Entry, void),

        root: *Entry,
        cwd_entry: *Entry,

        const Self = @This();
        const log = std.log.scoped(config.logging_scope);

        pub fn init(allocator: std.mem.Allocator, fsd: *const FileSystemDescription) !Self {
            var self: Self = .{
                .allocator = allocator,
                .entries = .{},
                .root = undefined,
                .cwd_entry = undefined,
            };
            errdefer self.deinit();

            try self.entries.ensureTotalCapacity(allocator, @intCast(u32, fsd.entries.items.len));

            const ptr_to_inital_cwd = &fsd.entries.items[fsd.getCwd()];

            var opt_root: ?*Entry = null;
            var opt_cwd_entry: ?*Entry = null;

            _ = try self.initAddDirAndRecurse(
                fsd,
                &fsd.entries.items[fsd.getRoot()],
                ptr_to_inital_cwd,
                &opt_root,
                &opt_cwd_entry,
            );

            if (opt_root) |root| {
                self.root = root;
            } else return error.NoRootDirectory;

            if (opt_cwd_entry) |cwd_entry| {
                self.cwd_entry = cwd_entry;
            } else return error.NoCwd;

            return self;
        }

        pub fn deinit(self: *Self) void {
            log.debug("deinitializing FileSystem", .{});
            var iter = self.entries.keyIterator();
            while (iter.next()) |entry| {
                entry.*.deinit(self.allocator);
            }
            self.entries.deinit(self.allocator);
            self.* = undefined;
        }

        fn initAddDirAndRecurse(
            self: *Self,
            fsd: *const FileSystemDescription,
            current_dir: *const FileSystemDescription.EntryDescription,
            ptr_to_inital_cwd: *const FileSystemDescription.EntryDescription,
            opt_root: *?*Entry,
            opt_cwd_entry: *?*Entry,
        ) std.mem.Allocator.Error!*Entry {
            std.debug.assert(current_dir.subdata == .dir);

            const dir_entry = try self.addDirEntry(current_dir.name);

            if (opt_root.* == null) opt_root.* = dir_entry;
            if (opt_cwd_entry.* == null and current_dir == ptr_to_inital_cwd) opt_cwd_entry.* = dir_entry;

            const dir_data = &dir_entry.subdata.dir;

            for (current_dir.subdata.dir.entries.items) |entry_index| {
                const entry = &fsd.entries.items[entry_index];

                const new_entry = switch (entry.subdata) {
                    .file => |file| try self.addFileEntry(entry.name, file.contents),
                    .dir => try self.initAddDirAndRecurse(fsd, entry, ptr_to_inital_cwd, opt_root, opt_cwd_entry),
                };

                try dir_data.addEntry(self.allocator, new_entry);
            }

            return dir_entry;
        }

        fn addFileEntry(self: *Self, name: []const u8, contents: []const u8) !*Entry {
            const dupe_name = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(dupe_name);

            const dupe_content = try self.allocator.dupe(u8, contents);
            errdefer self.allocator.free(dupe_content);

            var entry = try self.allocator.create(Entry);
            errdefer self.allocator.destroy(entry);

            entry.* = .{
                .name = dupe_name,
                .subdata = .{ .file = .{ .contents = dupe_content } },
            };

            try self.entries.putNoClobber(self.allocator, entry, {});

            return entry;
        }

        fn addDirEntry(self: *Self, name: []const u8) !*Entry {
            const dupe_name = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(dupe_name);

            var entry = try self.allocator.create(Entry);
            errdefer self.allocator.destroy(entry);

            entry.* = .{
                .name = dupe_name,
                .subdata = .{ .dir = .{} },
            };

            try self.entries.putNoClobber(self.allocator, entry, {});

            return entry;
        }

        pub fn cwd(self: *Self) Dir.Data.Custom {
            if (config.log) {
                log.info("cwd called", .{});
            }

            return .{
                .entry = self.cwd_entry,
            };
        }

        pub fn openFileFromDir(
            self: *Self,
            dir: Dir.Data.Custom,
            sub_path: []const u8,
            flags: File.OpenFlags,
        ) File.OpenError!File.Data.Custom {
            if (config.log) {
                log.info("openFileFromDir called, dir: {*}, sub_path: {s}, flags: {}", .{ dir.entry, sub_path, flags });
            }

            var parent: *Entry = if (std.fs.path.isAbsolute(sub_path)) self.root else self.cwd_entry;

            if (config.log) {
                log.debug("initial parent entry: {*}", .{parent});
            }

            var entry: *Entry = undefined;

            // TODO: Proper windows support
            var path_iter = std.mem.tokenize(u8, sub_path, std.fs.path.sep_str);
            path_loop: while (path_iter.next()) |section| {
                if (config.log) {
                    log.debug("section: {s}", .{section});
                }

                if (std.mem.eql(u8, section, ".")) {
                    if (config.log) {
                        log.debug("skipping current directory", .{});
                    }
                    continue;
                }
                if (std.mem.eql(u8, section, "..")) {
                    if (config.log) {
                        log.err("parent directory traversal is not yet implemented", .{});
                    }
                    @panic("unimplemented"); // TODO
                }

                for (parent.subdata.dir.entries.items) |child| {
                    if (std.mem.eql(u8, child.name, section)) {
                        if (config.log) {
                            log.debug("matching child found, entry: {*}, name: {s}", .{ child, child.name });
                        }
                        switch (child.subdata) {
                            .dir => {
                                if (config.log) {
                                    log.debug("child is directory", .{});
                                }
                                entry = child;
                                parent = child;
                                continue :path_loop;
                            },
                            .file => {
                                if (config.log) {
                                    log.debug("child is file", .{});
                                }
                                if (path_iter.next() != null) {
                                    if (config.log) {
                                        log.err("file encountered in middle of path", .{});
                                    }
                                    return File.OpenError.NotDir;
                                }
                                entry = child;
                                break :path_loop;
                            },
                        }
                    }
                } else {
                    if (config.log) {
                        log.err("parent directory {s} does not contain an entry {s}", .{ parent.name, section });
                    }
                    return File.OpenError.FileNotFound;
                }
            }

            entry.ref_count += 1;
            errdefer entry.ref_count -= 1;

            const view_index = try entry.addView(self.allocator);

            if (config.log) {
                log.debug("opened view, entry: {*}, name: {s}, index: {}", .{ entry, entry.name, view_index });
            }

            return File.Data.Custom{
                .entry = entry,
                .view_index = view_index,
            };
        }

        pub fn readFile(self: *Self, file: File.Data.Custom, buffer: []u8) std.os.ReadError!usize {
            _ = self;

            const entry = toEntry(file.entry);

            if (config.log) {
                log.info("readFile called, file: {*}, buffer len: {}", .{ entry, buffer.len });
            }

            switch (entry.subdata) {
                .dir => {
                    if (config.log) {
                        log.err("entry is a dir", .{});
                    }
                    return std.os.ReadError.IsDir;
                },
                .file => |f| {
                    const view = entry.views.getPtr(file.view_index) orelse return error.NotOpenForReading;

                    const size = std.math.min(buffer.len, f.contents.len - view.position);
                    const end = view.position + size;

                    std.mem.copy(u8, buffer[0..size], f.contents[view.position..end]);

                    view.position = end;

                    return size;
                },
            }
        }

        pub fn closeFile(self: *Self, file: File.Data.Custom) void {
            _ = self;

            const entry = toEntry(file.entry);

            if (config.log) {
                log.info("closeFile called, file: {*}", .{entry});
            }

            entry.ref_count -= 1;
            entry.removeView(file.view_index);

            if (config.log) {
                log.debug("closed view, entry: {x}, name: {s}, index: {}", .{ entry, entry.name, file.view_index });
            }
        }

        inline fn toEntry(ptr: *c_void) *Entry {
            return @ptrCast(*Entry, @alignCast(@alignOf(Entry), ptr));
        }
    };
}

pub const Entry = struct {
    ref_count: usize = 0,
    name: []const u8,

    // TODO: Reuse unused handles
    views_id_counter: u32 = 0,
    views: std.AutoHashMapUnmanaged(u32, View) = .{},

    subdata: SubData,

    const SubData = union(enum) {
        file: FileData,
        dir: DirData,

        const FileData = struct {
            contents: []const u8,
        };

        const DirData = struct {
            entries: std.ArrayListUnmanaged(*Entry) = .{},

            fn addEntry(self: *DirData, allocator: std.mem.Allocator, entry: *Entry) !void {
                try self.entries.append(allocator, entry);
            }
        };
    };

    const View = struct {
        index: u32,
        position: usize = 0,
    };

    fn addView(self: *Entry, allocator: std.mem.Allocator) !u32 {
        const index = self.views_id_counter;
        self.views_id_counter = std.math.add(u32, index, 1) catch return error.ProcessFdQuotaExceeded;
        errdefer self.views_id_counter -= 1;

        var get_or_put = self.views.getOrPut(allocator, index) catch return error.SystemResources;
        std.debug.assert(!get_or_put.found_existing);

        get_or_put.value_ptr.* = .{
            .index = index,
        };

        return index;
    }

    fn removeView(self: *Entry, index: u32) void {
        _ = self.views.remove(index);
    }

    fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.views.deinit(allocator);
        switch (self.subdata) {
            .file => |file| allocator.free(file.contents),
            .dir => |*dir| dir.entries.deinit(allocator),
        }
        allocator.destroy(self);
    }
};

comptime {
    @import("../Config.zig").referenceAllIterations(FileSystem);
}

comptime {
    std.testing.refAllDecls(@This());
}
