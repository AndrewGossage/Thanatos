const std = @import("std");
pub const c = @cImport({
    @cInclude("sqlite3.h");
});

pub var db: ?*c.sqlite3 = null;
var mut: std.Thread.Mutex = .{};
pub fn init() !void {
    mut.lock();
    mut.unlock();
    var rc: c_int = 0;
    // Open database with full mutex for thread safety
    rc = c.sqlite3_open_v2("test.db", &db, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX, null);
    if (rc != c.SQLITE_OK) {
        return error.DatabaseError;
    }
    rc = c.sqlite3_exec(db, "DROP TABLE IF EXISTS users;", null, null, null);
    if (rc != c.SQLITE_OK) {
        return error.SQLError;
    }
    const create_sql = "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT);";
    rc = c.sqlite3_exec(db, create_sql, null, null, null);
    if (rc != c.SQLITE_OK) {
        return error.SQLError;
    }
    rc = c.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, null);
    if (rc != c.SQLITE_OK) {
        return error.SQLError;
    }

    // Optional: Set busy timeout (milliseconds) for better concurrent access
    rc = c.sqlite3_busy_timeout(db, 5000);
    if (rc != c.SQLITE_OK) {
        return error.SQLError;
    }

    // Insert data
    for (0..1000) |_| {
        const insert_sql = "INSERT INTO users (name) VALUES ('Alice'), ('Bob');";
        rc = c.sqlite3_exec(db, insert_sql, null, null, null);
        if (rc != c.SQLITE_OK) {
            return error.SQLError;
        }
    }
}
pub fn run(allocator: std.mem.Allocator) ![]const u8 {
    var output: std.ArrayList(u8) = .{};
    errdefer output.deinit(allocator);
    const writer = output.writer(allocator);
    var rc: c_int = 0;
    mut.lock();
    mut.unlock();
    // Enable WAL mode
    // Create table

    // Query data
    const select_sql = "SELECT id, name FROM users;";
    var stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(db, select_sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        try writer.print("Failed to prepare statement: {s}\n", .{c.sqlite3_errmsg(db)});
        return error.SQLError;
    }
    defer _ = c.sqlite3_finalize(stmt);

    try writer.writeAll("Users:\n");
    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int(stmt, 0);
        const name = c.sqlite3_column_text(stmt, 1);
        try writer.print("  ID: {d}, Name: {s}\n", .{ id, name });
    }
    try writer.writeAll("Success! WAL mode enabled.\n");

    return output.toOwnedSlice(allocator);
}
