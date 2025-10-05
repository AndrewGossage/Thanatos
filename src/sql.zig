const std = @import("std");
pub const c = @cImport({
    @cInclude("sqlite3.h");
});

pub var db: ?*c.sqlite3 = null;
var mut: std.Thread.Mutex = .{};
var select_stmt: ?*c.sqlite3_stmt = null; // Reusable prepared statement

pub fn init() !void {
    mut.lock();
    defer mut.unlock();

    var rc: c_int = 0;

    rc = c.sqlite3_open_v2("test.db", &db, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX, null);
    if (rc != c.SQLITE_OK) {
        return error.DatabaseError;
    }

    rc = c.sqlite3_exec(db, "DROP TABLE IF EXISTS users;", null, null, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    const create_sql = "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT);";
    rc = c.sqlite3_exec(db, create_sql, null, null, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    // Optimize PRAGMA settings
    rc = c.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    rc = c.sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", null, null, null); // Faster with WAL
    if (rc != c.SQLITE_OK) return error.SQLError;

    rc = c.sqlite3_exec(db, "PRAGMA cache_size=-128000;", null, null, null); // 128MB cache
    if (rc != c.SQLITE_OK) return error.SQLError;

    rc = c.sqlite3_exec(db, "PRAGMA temp_store=MEMORY;", null, null, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    rc = c.sqlite3_exec(db, "PRAGMA mmap_size=268435456;", null, null, null); // 256MB mmap
    if (rc != c.SQLITE_OK) return error.SQLError;

    rc = c.sqlite3_busy_timeout(db, 5000);
    if (rc != c.SQLITE_OK) return error.SQLError;

    // Use transaction for bulk inserts
    rc = c.sqlite3_exec(db, "BEGIN TRANSACTION;", null, null, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    var insert_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(db, "INSERT INTO users (name) VALUES (?);", -1, &insert_stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLError;
    defer _ = c.sqlite3_finalize(insert_stmt);

    for (0..2000) |i| {
        const name = if (i % 2 == 0) "Alice" else "Bob";
        _ = c.sqlite3_bind_text(insert_stmt, 1, name.ptr, @intCast(name.len), c.SQLITE_STATIC);
        _ = c.sqlite3_step(insert_stmt);
        _ = c.sqlite3_reset(insert_stmt);
    }

    rc = c.sqlite3_exec(db, "COMMIT;", null, null, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    // Prepare the SELECT statement once for reuse
    const select_sql = "SELECT id, name FROM users;";
    rc = c.sqlite3_prepare_v2(db, select_sql, -1, &select_stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLError;
}

pub fn run(allocator: std.mem.Allocator) ![]const u8 {
    var output: std.ArrayList(u8) = .{};
    errdefer output.deinit(allocator);
    const writer = output.writer(allocator);

    mut.lock();
    defer mut.unlock();

    // Reset the prepared statement for reuse
    _ = c.sqlite3_reset(select_stmt);

    try writer.writeAll("Users:\n");

    while (c.sqlite3_step(select_stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int(select_stmt, 0);
        const name = c.sqlite3_column_text(select_stmt, 1);
        try writer.print("  ID: {d}, Name: {s}\n", .{ id, name });
    }

    try writer.writeAll("Success! WAL mode enabled.\n");

    return output.toOwnedSlice(allocator);
}

pub fn deinit() void {
    if (select_stmt) |stmt| {
        _ = c.sqlite3_finalize(stmt);
    }
    if (db) |database| {
        _ = c.sqlite3_close(database);
    }
}
