const std = @import("std");
const builtin = @import("builtin");
const is_windows: bool = builtin.os.tag == .windows;

const System = @import("../interface/System.zig").System;
const Dir = @import("../interface/Dir.zig").Dir;
const File = @import("../interface/File.zig").File;

const Config = @import("../config/Config.zig").Config;
const FileSystemDescription = @import("../config/FileSystemDescription.zig").FileSystemDescription;

pub fn FileSystem(comptime config: Config) type {
    if (!config.file_system) return struct {};

    return struct {
        allocator: std.mem.Allocator,

        entries: std.AutoHashMapUnmanaged(*Entry, void),
        views: std.AutoHashMapUnmanaged(*View, void),

        root: *Entry,
        cwd_entry: *Entry,

        const CWD = @intToPtr(*anyopaque, std.mem.alignBackward(std.math.maxInt(usize), @alignOf(View)));

        const Self = @This();
        const FileSystemType = Self;

        const log = std.log.scoped(config.logging_scope);

        // ** INITALIZATION **

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

            var opt_root: ?*Entry = null;
            var opt_cwd_entry: ?*Entry = null;

            _ = try self.initAddDirAndRecurse(
                fsd,
                fsd.root,
                fsd.getCwd(),
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
            if (config.log) {
                log.debug("deinitializing FileSystem", .{});
            }

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

            for (current_dir.subdata.dir.entries.items) |entry| {
                const new_entry: *Entry = switch (entry.subdata) {
                    .file => |file| try self.addFileEntry(entry.name, file.contents),
                    .dir => try self.initAddDirAndRecurse(fsd, entry, ptr_to_inital_cwd, opt_root, opt_cwd_entry),
                };

                try dir_entry.addEntry(new_entry);
            }

            return dir_entry;
        }

        // ** INTERNAL API

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

        inline fn isCwd(ptr: *anyopaque) bool {
            return CWD == ptr;
        }

        inline fn toView(self: *Self, ptr: *anyopaque) ?*View {
            const view = @ptrCast(*View, @alignCast(@alignOf(View), ptr));
            if (self.views.contains(view)) {
                return view;
            }
            return null;
        }

        fn cwdOrEntry(self: *Self, ptr: *anyopaque) ?*Entry {
            if (isCwd(ptr)) return self.cwd_entry;
            if (self.toView(ptr)) |v| return v.entry;
            return null;
        }

        fn resolveSearchRootFromPath(self: *Self, possible_parent: *Entry, path: []const u8) *Entry {
            return if (std.fs.path.isAbsolute(path)) self.root else possible_parent;
        }

        fn resolveEntry(self: *Self, search_root: *Entry, path: []const u8) !?*Entry {
            _ = self;
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
                log.info("cwd called", .{});
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
                log.info("openFileFromDir called, entry: {*}, sub_path: \"{s}\", flags: {}", .{ dir_entry, sub_path, flags });
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

        pub fn readFile(self: *Self, ptr: *anyopaque, buffer: []u8) std.os.ReadError!usize {
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

                    std.mem.copy(u8, buffer, file.contents[view.position..end]);

                    view.position = end;

                    return size;
                },
            }
        }

        pub fn closeFile(self: *Self, ptr: *anyopaque) void {
            const view = self.toView(ptr) orelse return;

            if (config.log) {
                log.info("closeFile called, view: {*}", .{view});
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

            allocator: std.mem.Allocator,
            file_system: *FileSystemType,

            const SubData = union(enum) {
                file: FileData,
                dir: DirData,

                const FileData = struct {
                    contents: []const u8,
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
            ) !*Entry {
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
                    if (config.log) {
                        log.debug("entry {*} reference count reached zero, entry name: \"{s}\"", .{ self, self.name });
                    }
                    self.deinit();
                    return true;
                }

                return false;
            }

            fn setParent(self: *Entry, parent: *Entry) !void {
                if (self.parent) |old_parent| {
                    _ = old_parent.decrementReference();
                } else {
                    self.incrementReference();
                }

                self.parent = parent;
            }

            /// Returns `true` if the entry has been destroyed
            fn unsetParent(self: *Entry) bool {
                if (self.parent) |old_parent| {
                    _ = old_parent.decrementReference();
                }

                if (self.decrementReference()) {
                    return true;
                }

                self.parent = null;
                return false;
            }

            fn addEntry(self: *Entry, entry: *Entry) !void {
                std.debug.assert(self.subdata == .dir);

                self.incrementReference();
                errdefer _ = self.decrementReference();

                if (try self.subdata.dir.entries.fetchPut(self.allocator, entry, {})) |_| {
                    return error.DuplicateEntry;
                }
                errdefer _ = self.subdata.dir.entries.swapRemove(entry);

                try entry.setParent(self);
            }

            /// Returns true if the entry has been destroyed
            fn removeEntry(self: *Entry, entry: *Entry) bool {
                std.debug.assert(self.subdata == .dir);

                if (self.subdata.dir.entries.fetchSwapRemove(entry)) |e| {
                    return e.key.unsetParent();
                }

                return false;
            }

            fn deinit(self: *Entry) void {
                self.allocator.free(self.name);
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
    @import("../config/Config.zig").referenceAllIterations(FileSystem);
}

comptime {
    std.testing.refAllDecls(@This());
}
