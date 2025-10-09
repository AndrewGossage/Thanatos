const std = @import("std");

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

// Thread-local storage - each thread gets its own connection and statement
threadlocal var thread_db: ?*c.sqlite3 = null;
threadlocal var thread_stmt: ?*c.sqlite3_stmt = null;
threadlocal var thread_initialized: bool = false;

// Template cache (shared across all threads, read-only after init)
var template_cache: []const u8 = undefined;
var template_allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    // Create a single write connection for initialization
    var db: ?*c.sqlite3 = null;
    var rc = c.sqlite3_open_v2("test.db", &db, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX, null);
    if (rc != c.SQLITE_OK) return error.DatabaseError;
    defer _ = c.sqlite3_close(db);

    _ = c.sqlite3_exec(db, "DROP TABLE IF EXISTS users;", null, null, null);

    const create_sql = "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT);";
    rc = c.sqlite3_exec(db, create_sql, null, null, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    // Optimize PRAGMA settings
    _ = c.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, null);
    _ = c.sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", null, null, null);
    _ = c.sqlite3_exec(db, "PRAGMA cache_size=-256000;", null, null, null);
    _ = c.sqlite3_exec(db, "PRAGMA temp_store=MEMORY;", null, null, null);
    _ = c.sqlite3_exec(db, "PRAGMA mmap_size=268435456;", null, null, null);

    // Bulk insert with transaction
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

    // Load and cache the template
    template_allocator = allocator;
    const file = try std.fs.cwd().openFile("pages/resp.html", .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const buffer = try allocator.alloc(u8, file_size);
    const bytes_read = try file.readAll(buffer);
    template_cache = buffer[0..bytes_read];
}

fn initThreadLocal() !void {
    if (thread_initialized) return;

    var rc = c.sqlite3_open_v2("test.db", &thread_db, c.SQLITE_OPEN_READONLY | c.SQLITE_OPEN_NOMUTEX, null);
    if (rc != c.SQLITE_OK) return error.DatabaseError;

    // Configure connection (read-only optimizations)
    _ = c.sqlite3_exec(thread_db, "PRAGMA query_only=ON;", null, null, null);
    _ = c.sqlite3_exec(thread_db, "PRAGMA temp_store=MEMORY;", null, null, null);
    _ = c.sqlite3_exec(thread_db, "PRAGMA cache_size=-64000;", null, null, null);

    // Prepare the SELECT statement
    const select_sql = "SELECT id, name FROM users;";
    rc = c.sqlite3_prepare_v2(thread_db, select_sql, -1, &thread_stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLError;

    thread_initialized = true;
}

pub fn run(allocator: std.mem.Allocator) ![]const u8 {
    // Initialize thread-local connection on first use
    try initThreadLocal();

    var output: std.ArrayList(u8) = .{};

    errdefer output.deinit(allocator);
    const writer = output.writer(allocator);

    // NO MUTEX - using thread-local storage!
    _ = c.sqlite3_reset(thread_stmt);

    try writer.writeAll("Users:\n");

    while (c.sqlite3_step(thread_stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int(thread_stmt, 0);
        const name = c.sqlite3_column_text(thread_stmt, 1);
        try writer.print("  ID: {d}, Name: {s}\n", .{ id, name });
    }

    try writer.writeAll("Success! WAL mode enabled.\n");

    return output.toOwnedSlice(allocator);
}

pub fn renderResponse(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    // Find $value$ in template and replace it
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const needle = "$value$";
    var start: usize = 0;

    while (std.mem.indexOfPos(u8, template_cache, start, needle)) |pos| {
        // Append everything before $value$
        try result.appendSlice(template_cache[start..pos]);
        // Append the actual value
        try result.appendSlice(value);
        // Move past $value$
        start = pos + needle.len;
    }

    // Append remainder
    try result.appendSlice(template_cache[start..]);

    return result.toOwnedSlice();
}

pub fn deinit() void {
    // Clean up thread-local resources
    if (thread_stmt) |stmt| {
        _ = c.sqlite3_finalize(stmt);
        thread_stmt = null;
    }
    if (thread_db) |db| {
        _ = c.sqlite3_close(db);
        thread_db = null;
    }
    thread_initialized = false;

    // Clean up template cache
    template_allocator.free(template_cache);
}

// Call this from each thread when it exits (if you have thread cleanup)
pub fn deinitThread() void {
    if (thread_stmt) |stmt| {
        _ = c.sqlite3_finalize(stmt);
        thread_stmt = null;
    }
    if (thread_db) |db| {
        _ = c.sqlite3_close(db);
        thread_db = null;
    }
    thread_initialized = false;
}
