const std = @import("std");
const builtin = @import("builtin");
const is_windows: bool = builtin.os.tag == .windows;

const Backend = @import("Backend.zig");

const System = @import("../interface/System.zig");
const Dir = @import("../interface/Dir.zig");
const File = @import("../interface/File.zig");

const Config = @import("../config/Config.zig");
const FileSystemDescription = @import("../config/FileSystemDescription.zig");

pub fn FileSystem(comptime config: Config) type {
    if (!config.file_system) return struct {};

    return struct {
        allocator: std.mem.Allocator,
        system: System,

        entries: std.AutoHashMapUnmanaged(*Entry, void),
        views: std.AutoHashMapUnmanaged(*View, void),

        root: *Entry,
        cwd_entry: *Entry,

        // TODO: Implement proper permissions
        const DEFAULT_PERMISSIONS: std.os.mode_t = blk: {
            var permissions: std.os.mode_t = 0;

            permissions |= std.os.S.IRWXU; // RWX for owner
            permissions |= std.os.S.IRWXG; // RWX for group
            permissions |= std.os.S.IRWXO; // RWX for other

            break :blk permissions;
        };

        const CWD = @intToPtr(*anyopaque, std.mem.alignBackward(std.math.maxInt(usize), @alignOf(View)));

        const Self = @This();
        const FileSystemType = Self;

        const log = std.log.scoped(config.logging_scope);

        // ** INITALIZATION **

        pub fn create(allocator: std.mem.Allocator, system: System, fsd: *const FileSystemDescription) !Self {
            var self: Self = .{
                .allocator = allocator,
                .system = system,
                .entries = .{},
                .views = .{},
                .root = undefined,
                .cwd_entry = undefined,
            };
            errdefer self.destroy();

            try self.entries.ensureTotalCapacity(allocator, @intCast(u32, fsd.entries.items.len));

            var opt_root: ?*Entry = null;
            var opt_cwd_entry: ?*Entry = null;

            _ = try self.initAddDirAndRecurse(
                fsd,
                fsd.root,
                fsd.getCwd(),
                &opt_root,
                &opt_cwd_entry,
                system.nanoTimestamp(),
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

        pub fn destroy(self: *Self) void {
            if (config.log) {
                log.debug("destroying FileSystem", .{});
            }

            {
                var iter = self.views.keyIterator();
                while (iter.next()) |view| {
                    view.*.destroy();
                }
                self.views.deinit(self.allocator);
            }

            {
                var iter = self.entries.keyIterator();
                while (iter.next()) |entry| {
                    entry.*.destroy();
                }
                self.entries.deinit(self.allocator);
            }
        }

        fn initAddDirAndRecurse(
            self: *Self,
            fsd: *const FileSystemDescription,
            current_dir: *const FileSystemDescription.EntryDescription,
            ptr_to_inital_cwd: *const FileSystemDescription.EntryDescription,
            opt_root: *?*Entry,
            opt_cwd_entry: *?*Entry,
            current_time: i128,
        ) (error{DuplicateEntry} || std.mem.Allocator.Error)!*Entry {
            std.debug.assert(current_dir.subdata == .dir);

            const dir_entry = try self.addDirEntry(current_dir.name, current_time);

            if (opt_root.* == null) opt_root.* = dir_entry;
            if (opt_cwd_entry.* == null and current_dir == ptr_to_inital_cwd) opt_cwd_entry.* = dir_entry;

            for (current_dir.subdata.dir.entries.values()) |entry| {
                const new_entry: *Entry = switch (entry.subdata) {
                    .file => |file| try self.addFileEntry(entry.name, file.contents, current_time),
                    .dir => try self.initAddDirAndRecurse(
                        fsd,
                        entry,
                        ptr_to_inital_cwd,
                        opt_root,
                        opt_cwd_entry,
                        current_time,
                    ),
                };

                try dir_entry.addEntry(new_entry, current_time);
            }

            return dir_entry;
        }

        // ** INTERNAL API

        /// Create a file entry and add it to the `entries` hash map
        fn addFileEntry(self: *Self, name: []const u8, contents: []const u8, current_time: i128) !*Entry {
            const entry = try Entry.createFile(self.allocator, self, name, contents, current_time);
            errdefer entry.destroy();

            try self.entries.putNoClobber(self.allocator, entry, {});

            return entry;
        }

        /// Create a dir entry and add it to the `entries` hash map
        fn addDirEntry(self: *Self, name: []const u8, current_time: i128) !*Entry {
            const entry = try Entry.createDir(self.allocator, self, name, current_time);
            errdefer entry.destroy();

            try self.entries.putNoClobber(self.allocator, entry, {});

            return entry;
        }

        /// Add a view to the given entry
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

        /// Remove a view from the given entry
        fn removeView(self: *Self, view: *View) void {
            _ = view.entry.decrementReference();
            _ = self.views.remove(view);
            view.destroy();
        }

        /// Set the current working directory
        fn setCwd(self: *Self, entry: *Entry, dereference_old_cwd: bool) !void {
            entry.incrementReference();
            if (dereference_old_cwd) _ = self.cwd_entry.decrementReference();
            self.cwd_entry = entry;
        }

        /// Check if the given pointer is the current working directory
        inline fn isCwd(ptr: *anyopaque) bool {
            return CWD == ptr;
        }

        /// Cast the given `ptr` to a view if it is one.
        inline fn toView(self: *Self, ptr: *anyopaque) ?*View {
            const view = @ptrCast(*View, @alignCast(@alignOf(View), ptr));
            if (self.views.contains(view)) {
                return view;
            }
            return null;
        }

        /// Return the entry associated with the given view, if there is one.
        fn cwdOrEntry(self: *Self, ptr: *anyopaque) ?*Entry {
            if (isCwd(ptr)) return self.cwd_entry;
            if (self.toView(ptr)) |v| return v.entry;
            return null;
        }

        /// Returns the search root associated with the given path
        fn resolveSearchRootFromPath(self: *Self, possible_parent: *Entry, path: []const u8) *Entry {
            return if (std.fs.path.isAbsolute(path)) self.root else possible_parent;
        }

        /// Searches from the search root for the entry specified by the given path
        fn resolveEntry(self: *Self, search_root: *Entry, path: []const u8) !?*Entry {
            var entry: *Entry = undefined;
            var search_entry = search_root;

            var path_iter = std.mem.tokenize(u8, path, std.fs.path.sep_str);
            path_loop: while (path_iter.next()) |section| {
                if (config.log) {
                    log.debug("current search entry: {*}, search entry name: \"{s}\", section: \"{s}\"", .{
                        search_entry,
                        search_entry.name,
                        section,
                    });
                }

                if (section.len == 0) continue;

                if (std.mem.eql(u8, section, ".")) {
                    if (config.log) {
                        log.debug("skipping current directory section", .{});
                    }
                    continue;
                }
                if (std.mem.eql(u8, section, "..")) {
                    if (config.log) {
                        log.debug("traverse to parent directory section", .{});
                    }

                    if (search_entry.parent) |search_entry_parent| {
                        entry = search_entry_parent;
                        search_entry = search_entry_parent;
                    } else if (search_entry != self.root) {
                        // TODO: This should instead return an error, but what error? FileNotFound?
                        @panic("attempted to traverse to parent of search entry with no parent");
                    }

                    continue;
                }

                var iter = search_entry.subdata.dir.entries.iterator();
                while (iter.next()) |e| {
                    const child = e.key_ptr.*;
                    if (std.mem.eql(u8, child.name, section)) {
                        if (config.log) {
                            log.debug("found entry: {*}, name: \"{s}\", type: {s}", .{ child, child.name, @tagName(child.subdata) });
                        }
                        switch (child.subdata) {
                            .dir => {
                                entry = child;
                                search_entry = child;
                                continue :path_loop;
                            },
                            .file => {
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
                        log.err("search directory \"{s}\" does not contain an entry \"{s}\"", .{ search_entry.name, section });
                    }
                    return null;
                }
            }

            return entry;
        }

        // ** EXTERNAL API

        pub fn cwd(self: *Self) *anyopaque {
            _ = self;

            if (config.log) {
                log.debug("cwd called", .{});
            }

            return CWD;
        }

        pub fn openFileFromDir(
            self: *Self,
            ptr: *anyopaque,
            sub_path: []const u8,
            flags: File.OpenFlags,
        ) File.OpenError!*anyopaque {
            if (is_windows) {
                // TODO: Implement windows
                @compileError("Windows support is unimplemented");
            }

            if (flags.mode != .read_only) {
                // TODO: Implement *not* read_only
                std.debug.panic("file mode '{s}' is unimplemented", .{@tagName(flags.mode)});
            }

            if (flags.lock != .None) {
                // TODO: Implement lock
                @panic("lock is unimplemented");
            }

            if (flags.allow_ctty) {
                @panic("allow_ctty is unsupported");
            }

            const dir_entry = self.cwdOrEntry(ptr) orelse return File.OpenError.NoDevice;

            if (config.log) {
                log.debug("openFileFromDir called, entry: {*}, sub_path: \"{s}\", flags: {}", .{ dir_entry, sub_path, flags });
            }

            const search_root = self.resolveSearchRootFromPath(dir_entry, sub_path);

            if (config.log) {
                log.debug("initial search entry: {*}, name: \"{s}\"", .{ search_root, search_root.name });
            }

            const entry = (try self.resolveEntry(search_root, sub_path)) orelse return File.OpenError.FileNotFound;

            const view = self.addView(entry) catch return error.SystemResources;

            if (config.log) {
                log.debug("opened view, view: {*}, entry: {*}, entry name: \"{s}\"", .{ view, entry, entry.name });
            }

            return view;
        }

        pub fn createFileFromDir(
            self: *Self,
            ptr: *anyopaque,
            sub_path: []const u8,
            flags: File.CreateFlags,
        ) File.OpenError!*anyopaque {
            if (is_windows) {
                // TODO: Implement windows
                @compileError("Windows support is unimplemented");
            }

            // TODO: Implement support for flags.mode
            // TODO: Implement support for flags.read

            if (flags.lock != .None) {
                // TODO: Implement lock
                @panic("lock is unimplemented");
            }

            const dir_entry = self.cwdOrEntry(ptr) orelse return File.OpenError.NoDevice;

            if (config.log) {
                log.debug("createFileFromDir called, entry: {*}, sub_path: \"{s}\", flags: {}", .{ dir_entry, sub_path, flags });
            }

            const search_root = self.resolveSearchRootFromPath(dir_entry, sub_path);

            if (config.log) {
                log.debug("initial search entry: {*}, name: \"{s}\"", .{ search_root, search_root.name });
            }

            const entry = blk: {
                if (try self.resolveEntry(search_root, sub_path)) |entry| {
                    // File already exists
                    if (flags.exclusive) {
                        return File.OpenError.PathAlreadyExists;
                    }

                    if (flags.truncate and entry.subdata == .file) {
                        // TODO: Check mode
                        entry.subdata.file.contents.items.len = 0;
                    }

                    break :blk entry;
                }

                @panic("TODO");
                // File doesn't exist
            };

            const view = self.addView(entry) catch return error.SystemResources;

            if (config.log) {
                log.debug("opened view, view: {*}, entry: {*}, entry name: \"{s}\"", .{ view, entry, entry.name });
            }

            return view;
        }

        pub fn readFile(self: *Self, ptr: *anyopaque, buffer: []u8) std.os.ReadError!usize {
            const view = self.toView(ptr) orelse return error.NotOpenForReading;

            if (config.log) {
                log.debug("readFile called, view: {*}, buffer len: {}", .{ view, buffer.len });
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
                    const slice = file.contents.items;

                    const size = std.math.min(buffer.len, slice.len - view.position);
                    const end = view.position + size;

                    std.mem.copy(u8, buffer, slice[view.position..end]);

                    view.position = end;

                    entry.atime = self.system.nanoTimestamp();

                    return size;
                },
            }
        }

        pub fn stat(self: *Self, ptr: *anyopaque) File.StatError!File.Stat {
            const view = self.toView(ptr) orelse unreachable;

            if (config.log) {
                log.debug("stat called, view: {*}", .{view});
            }

            const entry = view.entry;

            var stat_value: File.Stat = .{
                .inode = @ptrToInt(view.entry),
                .atime = entry.atime,
                .mtime = entry.mtime,
                .ctime = entry.ctime,
                .mode = entry.mode,

                .size = undefined,
                .kind = undefined,
            };

            switch (entry.subdata) {
                .dir => |dir| {
                    stat_value.size = dir.entries.count() * @sizeOf(*Entry); // TODO: What should this be?
                    stat_value.kind = .Directory;
                },
                .file => |file| {
                    stat_value.size = file.contents.items.len;
                    stat_value.kind = .File;
                },
            }

            return stat_value;
        }

        pub fn updateTimes(self: *Self, ptr: *anyopaque, atime: i128, mtime: i128) File.UpdateTimesError!void {
            const view = self.toView(ptr) orelse unreachable;

            if (config.log) {
                log.debug("updateTimes called, view: {*}, atime: {}, mtime: {}", .{ view, atime, mtime });
            }

            const entry = view.entry;

            entry.atime = atime;
            entry.mtime = mtime;
        }

        pub fn closeFile(self: *Self, ptr: *anyopaque) void {
            const view = self.toView(ptr) orelse return;

            if (config.log) {
                log.debug("closeFile called, view: {*}", .{view});
            }

            if (config.log) {
                log.debug("closed view {*}, entry: {*}, entry name: \"{s}\"", .{ view, view.entry, view.entry.name });
            }

            self.removeView(view);
        }

        const Entry = struct {
            ref_count: usize = 0,
            name: []const u8,
            subdata: SubData,

            parent: ?*Entry = null,

            /// time of last access
            atime: i128 = 0,
            /// time of last modification
            mtime: i128 = 0,
            /// time of last status change
            ctime: i128 = 0,

            // TODO: Implement proper permissions
            mode: std.os.mode_t = DEFAULT_PERMISSIONS,

            allocator: std.mem.Allocator,
            file_system: *FileSystemType,

            const SubData = union(enum) {
                file: FileData,
                dir: DirData,

                const FileData = struct {
                    contents: std.ArrayListUnmanaged(u8),
                };

                const DirData = struct {
                    entries: std.AutoArrayHashMapUnmanaged(*Entry, void) = .{},
                };
            };

            fn createFile(
                allocator: std.mem.Allocator,
                file_system: *FileSystemType,
                name: []const u8,
                contents: []const u8,
                current_time: i128,
            ) !*Entry {
                const dupe_name = try allocator.dupe(u8, name);
                errdefer allocator.free(dupe_name);

                var new_contents = try std.ArrayListUnmanaged(u8).initCapacity(allocator, contents.len);
                errdefer new_contents.deinit(allocator);

                new_contents.insertSlice(allocator, 0, contents) catch unreachable;

                var entry = try allocator.create(Entry);
                errdefer allocator.destroy(entry);

                entry.* = .{
                    .allocator = allocator,
                    .file_system = file_system,
                    .name = dupe_name,
                    .atime = current_time,
                    .mtime = current_time,
                    .ctime = current_time,
                    .subdata = .{ .file = .{ .contents = new_contents } },
                };

                return entry;
            }

            fn createDir(
                allocator: std.mem.Allocator,
                file_system: *FileSystemType,
                name: []const u8,
                current_time: i128,
            ) !*Entry {
                const dupe_name = try allocator.dupe(u8, name);
                errdefer allocator.free(dupe_name);

                var entry = try allocator.create(Entry);
                errdefer allocator.destroy(entry);

                entry.* = .{
                    .allocator = allocator,
                    .file_system = file_system,
                    .name = dupe_name,
                    .atime = current_time,
                    .mtime = current_time,
                    .ctime = current_time,
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
                    if (config.log) {
                        log.debug("entry {*} reference count reached zero, entry name: \"{s}\"", .{ self, self.name });
                    }
                    self.destroy();
                    return true;
                }

                return false;
            }

            /// Add an entry to the parent entry.
            /// The parent entry must be a directory.
            fn addEntry(parent: *Entry, entry: *Entry, current_time: i128) !void {
                std.debug.assert(parent.subdata == .dir);

                if (try parent.subdata.dir.entries.fetchPut(parent.allocator, entry, {})) |_| {
                    return error.DuplicateEntry;
                }

                if (entry.parent) |old_parent| {
                    old_parent.ctime = current_time;
                } else {
                    entry.incrementReference();
                }

                entry.ctime = current_time;

                entry.parent = parent;
                parent.ctime = current_time;
            }

            /// Remove an entry from the given entry
            /// `self` must be a directory
            /// Returns true if the entry has been destroyed
            fn removeEntry(self: *Entry, entry: *Entry, current_time: i128) bool {
                std.debug.assert(self.subdata == .dir);

                if (self.subdata.dir.entries.fetchSwapRemove(entry)) |_| {
                    self.ctime = current_time;

                    if (entry.decrementReference()) {
                        return true;
                    }

                    entry.ctime = current_time;
                    entry.parent = null;
                    return false;
                }

                return false;
            }

            fn destroy(self: *Entry) void {
                self.allocator.free(self.name);
                switch (self.subdata) {
                    .file => |*file| file.contents.deinit(self.allocator),
                    .dir => |*dir| dir.entries.deinit(self.allocator),
                }
                self.allocator.destroy(self);
            }
        };

        const View = struct {
            entry: *Entry,
            position: usize = 0,

            file_system: *FileSystemType,

            pub fn destroy(self: *View) void {
                self.file_system.allocator.destroy(self);
            }
        };
    };
}

comptime {
    @import("../internal.zig").referenceAllIterations(FileSystem);
}

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
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
}
