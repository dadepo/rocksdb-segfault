const std = @import("std");
const rocks = @import("rocksdb");
const config = @import("config");

const allocator = std.heap.c_allocator;
const WriteBatch = rocks.WriteBatch;

const Db = struct {
    allocator: std.mem.Allocator,
    cf_handle: rocks.ColumnFamilyHandle,
    db: rocks.DB,
    path: []const u8,

    const Self = @This();

    pub fn initWriteBatch(_: *Self) WriteBatch {
        return rocks.WriteBatch.init();
    }
};

var err_str: ?rocks.Data = null;

pub fn main() !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const path = "src/repro/blockstore";

    if (config.freshDb) {
        if (std.fs.cwd().access(path, .{})) |_| {
            try std.fs.cwd().deleteTree(path);
        } else |_| {}
        try std.fs.cwd().makePath(path);
    }

    var db: Db = try open(allocator, path);

    {
        var writer_thread = try std.Thread.spawn(.{}, writer, .{&db});
        defer writer_thread.join();
        var deleter_thread = try std.Thread.spawn(.{}, deleter, .{&db});
        defer deleter_thread.join();
        var reader_thread = try std.Thread.spawn(.{}, reader, .{&db});
        defer reader_thread.join();
    }
}

pub fn open(allocator_: std.mem.Allocator, path_: []const u8) !Db {
    const owned_path = try allocator_.dupe(u8, path_);

    // allocate cf descriptions
    const column_family_descriptions = try allocator.alloc(rocks.ColumnFamilyDescription, 1);
    defer allocator.free(column_family_descriptions);

    // initialize cf descriptions
    column_family_descriptions[0] = .{ .name = "default", .options = .{} };

    // open rocksdb
    const db_: rocks.DB, //
    const cfs: []const rocks.ColumnFamily //
    = try rocks.DB.open(
        allocator_,
        owned_path,
        .{ .create_if_missing = true, .create_missing_column_families = true },
        column_family_descriptions,
        &err_str,
    );
    defer allocator_.free(cfs);

    var cf_handle_ = try allocator.create(rocks.ColumnFamilyHandle);
    errdefer allocator.destroy(cf_handle_); // kept alive as a field
    var h = cfs[0].handle;
    // initialize handle slice
    cf_handle_ = &h;

    return .{
        .allocator = allocator_,
        .db = db_,
        .cf_handle = cf_handle_.*,
        .path = owned_path,
    };
}

fn writer(db_: *Db) !void {
    var rng = std.rand.DefaultPrng.init(1234);
    while (true) {
        var index_buffer: [8]u8 = undefined;
        for (0..index_buffer.len) |i| {
            index_buffer[i] = @intCast(rng.random().int(u8));
        }
        const index: []const u8 = index_buffer[0..];

        var buffer: [61]u8 = undefined;

        // Fill the buffer with random bytes
        for (0..buffer.len) |i| {
            buffer[i] = @intCast(rng.random().int(u8));
        }

        const slice: []const u8 = buffer[0..];
        try rocks.DB.put(&db_.db, db_.cf_handle, index, slice, &err_str);
        std.debug.print("Wrote random data\n", .{});
    }
}

fn deleter(db_: *Db) !void {
    var rng = std.rand.DefaultPrng.init(123);
    while (true) {
        const start = rng.random().int(u32);
        const end = blk: {
            const end_ = rng.random().int(u32);
            if (end_ < start)
                break :blk (end_ +| start)
            else
                break :blk end_;
        };
        var batch = db_.initWriteBatch();
        defer batch.deinit();
        // std.debug.print("Deleting. Start:{} End: {}\n", .{ start, end });
        var start_buffer: [4]u8 = undefined;
        var end_buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &start_buffer, start, .big);
        std.mem.writeInt(u32, &end_buffer, end, .big);
        batch.deleteRange(db_.cf_handle, &start_buffer, &end_buffer);
        try rocks.DB.write(&db_.db, batch, &err_str);
        // std.debug.print("Deleted. Start:{} End: {}\n", .{ start, end });
    }
}

fn reader(db_: *Db) !void {
    var rng = std.rand.DefaultPrng.init(12345);
    while (true) {
        var index_buffer: [8]u8 = undefined;
        for (0..index_buffer.len) |i| {
            index_buffer[i] = @intCast(rng.random().int(u8));
        }
        const index: []const u8 = index_buffer[0..];

        const read = try rocks.DB.get(&db_.db, db_.cf_handle, index, &err_str);
        if (read) |_| {
            // std.debug.print("Read key {}\n", .{index});
        } else {
            // std.debug.print("Did not read deleted key {}\n", .{index});
        }
    }
}
