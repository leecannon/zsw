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
        views: std.AutoHashMapUnmanaged(*View, void),

        root: *Entry,
        cwd_entry: *Entry,

        const CWD = @intToPtr(*c_void, std.mem.alignBackward(std.math.maxInt(usize), @alignOf(View)));

        const Self = @This();
        const FileSystemType = Self;

        const log = std.log.scoped(config.logging_scope);

        pub fn init(allocator: std.mem.Allocator, fsd: *const FileSystemDescription) !*Self {
            var self = try allocator.create(Self);

            self.* = .{
                .allocator = allocator,
                .entries = .{},
                .views = .{},
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
                self.root.incrementReference();
            } else return error.NoRootDirectory;

            if (opt_cwd_entry) |cwd_entry| {
                try self.setCwd(cwd_entry, false);
            } else return error.NoCwd;

            return self;
        }

        pub fn deinit(self: *Self) void {
            log.debug("deinitializing FileSystem", .{});

            {
                var iter = self.views.keyIterator();
                while (iter.next()) |view| {
                    view.*.deinit();
                }
                self.views.deinit(self.allocator);
            }

            {
                var iter = self.entries.keyIterator();
                while (iter.next()) |entry| {
                    entry.*.deinit();
                }
                self.entries.deinit(self.allocator);
            }

            self.allocator.destroy(self);
        }

        fn initAddDirAndRecurse(
            self: *Self,
            fsd: *const FileSystemDescription,
            current_dir: *const FileSystemDescription.EntryDescription,
            ptr_to_inital_cwd: *const FileSystemDescription.EntryDescription,
            opt_root: *?*Entry,
            opt_cwd_entry: *?*Entry,
        ) (error{DuplicateEntry} || std.mem.Allocator.Error)!*Entry {
            std.debug.assert(current_dir.subdata == .dir);

            const dir_entry = try self.addDirEntry(current_dir.name);

            if (opt_root.* == null) opt_root.* = dir_entry;
            if (opt_cwd_entry.* == null and current_dir == ptr_to_inital_cwd) opt_cwd_entry.* = dir_entry;

            for (current_dir.subdata.dir.entries.items) |entry_index| {
                const entry: *const FileSystemDescription.EntryDescription = &fsd.entries.items[entry_index];

                const new_entry: *Entry = switch (entry.subdata) {
                    .file => |file| try self.addFileEntry(entry.name, file.contents),
                    .dir => try self.initAddDirAndRecurse(fsd, entry, ptr_to_inital_cwd, opt_root, opt_cwd_entry),
                };

                try dir_entry.addEntry(new_entry);
            }

            return dir_entry;
        }

        fn addFileEntry(self: *Self, name: []const u8, contents: []const u8) !*Entry {
            const entry = try Entry.createFile(self.allocator, self, name, contents);
            errdefer entry.deinit();

            try self.entries.putNoClobber(self.allocator, entry, {});

            return entry;
        }

        fn addDirEntry(self: *Self, name: []const u8) !*Entry {
            const entry = try Entry.createDir(self.allocator, self, name);
            errdefer entry.deinit();

            try self.entries.putNoClobber(self.allocator, entry, {});

            return entry;
        }

        fn addView(self: *Self, entry: *Entry) !*View {
            entry.incrementReference();
            errdefer _ = entry.decrementReference();

            var view = try self.allocator.create(View);
            errdefer self.allocator.destroy(view);

            view.* = .{
                .entry = entry,
                .file_system = self,
            };

            try self.views.putNoClobber(self.allocator, view, {});

            return view;
        }

        fn removeView(self: *Self, view: *View) void {
            _ = view.entry.decrementReference();
            _ = self.views.remove(view);
            view.deinit();
        }

        fn setCwd(self: *Self, entry: *Entry, dereference_old_cwd: bool) !void {
            entry.incrementReference();
            if (dereference_old_cwd) _ = self.cwd_entry.decrementReference();
            self.cwd_entry = entry;
        }

        inline fn isCwd(ptr: *c_void) bool {
            return CWD == ptr;
        }

        pub fn cwd(self: *Self) *c_void {
            _ = self;

            if (config.log) {
                log.info("cwd called", .{});
            }

            return CWD;
        }

        pub fn openFileFromDir(
            self: *Self,
            ptr: *c_void,
            sub_path: []const u8,
            flags: File.OpenFlags,
        ) File.OpenError!*c_void {
            const dir_entry = if (isCwd(ptr)) self.cwd_entry else blk: {
                const dir_view = self.toView(ptr) orelse return File.OpenError.NoDevice;
                break :blk dir_view.entry;
            };

            if (config.log) {
                log.info("openFileFromDir called, entry: {*}, sub_path: {s}, flags: {}", .{ dir_entry, sub_path, flags });
            }

            var parent: *Entry = if (std.fs.path.isAbsolute(sub_path)) self.root else dir_entry;

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

                var iter = parent.subdata.dir.entries.iterator();
                while (iter.next()) |e| {
                    const child = Entry.toEntry(e.key_ptr.*);
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

            const view = self.addView(entry) catch return error.SystemResources;

            if (config.log) {
                log.debug("opened view, view: {*}, entry: {*}", .{ view, entry });
            }

            return view;
        }

        pub fn readFile(self: *Self, ptr: *c_void, buffer: []u8) std.os.ReadError!usize {
            const view = self.toView(ptr) orelse return error.NotOpenForReading;

            if (config.log) {
                log.info("readFile called, view: {*}, buffer len: {}", .{ view, buffer.len });
            }

            const entry = view.entry;

            switch (entry.subdata) {
                .dir => {
                    if (config.log) {
                        log.err("entry is a dir", .{});
                    }
                    return std.os.ReadError.IsDir;
                },
                .file => |file| {
                    const size = std.math.min(buffer.len, file.contents.len - view.position);
                    const end = view.position + size;

                    std.mem.copy(u8, buffer[0..size], file.contents[view.position..end]);

                    view.position = end;

                    return size;
                },
            }
        }

        pub fn closeFile(self: *Self, ptr: *c_void) void {
            const view = self.toView(ptr) orelse return;

            if (config.log) {
                log.info("closeFile called, view: {*}", .{view});
            }

            if (config.log) {
                log.debug("closed view {*}, entry: {*}, name: {s}", .{ view, view.entry, view.entry.name });
            }

            self.removeView(view);
        }

        inline fn toView(self: *Self, ptr: *c_void) ?*View {
            const view = @ptrCast(*View, @alignCast(@alignOf(View), ptr));
            if (self.views.contains(view)) {
                return view;
            }
            return null;
        }

        const Entry = struct {
            ref_count: usize = 0,
            name: []const u8,
            subdata: SubData,

            // BUG: Zig thinks std.AutoArrayHashMapUnmanaged(*Entry, void) is a dependency loop
            parents: std.AutoHashMapUnmanaged(*c_void, void) = .{},

            allocator: std.mem.Allocator,
            file_system: *FileSystemType,

            const SubData = union(enum) {
                file: FileData,
                dir: DirData,

                const FileData = struct {
                    contents: []const u8,
                };

                const DirData = struct {
                    // BUG: Zig thinks std.AutoArrayHashMapUnmanaged(*Entry, void) is a dependency loop
                    entries: std.AutoArrayHashMapUnmanaged(*c_void, void) = .{},
                };
            };

            inline fn toEntry(ptr: *c_void) *Entry {
                return @ptrCast(*Entry, @alignCast(@alignOf(Entry), ptr));
            }

            fn createFile(allocator: std.mem.Allocator, file_system: *FileSystemType, name: []const u8, contents: []const u8) !*Entry {
                const dupe_name = try allocator.dupe(u8, name);
                errdefer allocator.free(dupe_name);

                const dupe_content = try allocator.dupe(u8, contents);
                errdefer allocator.free(dupe_content);

                var entry = try allocator.create(Entry);
                errdefer allocator.destroy(entry);

                entry.* = .{
                    .allocator = allocator,
                    .file_system = file_system,
                    .name = dupe_name,
                    .subdata = .{ .file = .{ .contents = dupe_content } },
                };

                return entry;
            }

            fn createDir(allocator: std.mem.Allocator, file_system: *FileSystemType, name: []const u8) !*Entry {
                const dupe_name = try allocator.dupe(u8, name);
                errdefer allocator.free(dupe_name);

                var entry = try allocator.create(Entry);
                errdefer allocator.destroy(entry);

                entry.* = .{
                    .allocator = allocator,
                    .file_system = file_system,
                    .name = dupe_name,
                    .subdata = .{ .dir = .{} },
                };

                return entry;
            }

            fn incrementReference(self: *Entry) void {
                self.ref_count += 1;
            }

            /// Returns `true` if the entry has been destroyed
            fn decrementReference(self: *Entry) bool {
                self.ref_count -= 1;

                if (self.ref_count == 0) {
                    self.deinit();
                    return true;
                }

                return false;
            }

            fn addParent(self: *Entry, parent: *Entry) !void {
                self.incrementReference();
                errdefer _ = self.decrementReference();

                if (try self.parents.fetchPut(self.allocator, parent, {})) |_| {
                    _ = self.decrementReference();
                }
            }

            /// Returns `true` if the entry has been destroyed
            fn removeParent(self: *Entry, parent: *Entry) bool {
                if (self.parents.remove(parent)) return self.decrementReference();
                return false;
            }

            fn addEntry(self: *Entry, entry: *Entry) !void {
                std.debug.assert(self.subdata == .dir);

                self.incrementReference();
                errdefer _ = self.decrementReference();

                if (try self.subdata.dir.entries.fetchPut(self.allocator, entry, {})) |_| {
                    _ = self.decrementReference();
                    return error.DuplicateEntry;
                }
                errdefer _ = self.subdata.dir.entries.swapRemove(entry);

                try entry.addParent(self);
            }

            /// Returns true if the entry has been destroyed
            fn removeEntry(self: *Entry, entry: *Entry) bool {
                std.debug.assert(self.subdata == .dir);

                if (self.subdata.dir.entries.fetchSwapRemove(entry)) |e| {
                    _ = toEntry(e.key).removeParent(self);
                    return self.decrementReference();
                }

                return false;
            }

            fn deinit(self: *Entry) void {
                self.allocator.free(self.name);
                self.parents.deinit(self.allocator);
                switch (self.subdata) {
                    .file => |file| self.allocator.free(file.contents),
                    .dir => |*dir| dir.entries.deinit(self.allocator),
                }
                self.allocator.destroy(self);
            }

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        const View = struct {
            entry: *Entry,
            position: usize = 0,

            file_system: *FileSystemType,

            pub fn deinit(self: *View) void {
                self.file_system.allocator.destroy(self);
            }

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        comptime {
            std.testing.refAllDecls(@This());
        }
    };
}

comptime {
    @import("../Config.zig").referenceAllIterations(FileSystem);
}

comptime {
    std.testing.refAllDecls(@This());
}
