const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const fmt = @import("fmt.zig");
const stdout = std.io.getStdOut().writer();
const builtin = @import("builtin");
const sql = @import("sql.zig");

pub const routes = &[_]server.Route{
    .{ .path = "/", .callback = index },
    .{ .path = "/home", .callback = index },
    .{ .path = "/styles/*", .callback = server.static },
    .{ .path = "/scripts/*", .callback = server.static },
    .{ .path = "/pages/*", .callback = server.static },
    .{ .path = "/api/get", .method = .GET, .callback = hxGet },
    .{ .path = "/api/sql", .method = .GET, .callback = sqlRoute },
    .{ .path = "/api/exec", .method = .POST, .callback = hxExec },
};

fn sqlRoute(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    var value: []const u8 = try sql.run(allocator);
    const query = server.Parser.query(IndexQuery, allocator, request);

    if (query != null) {
        value = try fmt.urlDecode(query.?.value orelse "default", allocator);
    }
    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("pages/resp.html", .{ .value = value }, heap);

    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

const IndexQuery = struct {
    value: ?[]const u8,
};
/// return index.html to the home route
fn index(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    var value: []const u8 = "This is a template string";
    const query = server.Parser.query(IndexQuery, allocator, request);

    if (query != null) {
        value = try fmt.urlDecode(query.?.value orelse "default", allocator);
    }
    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("index.html", .{ .value = value }, heap);

    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

fn hxGet(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    var value: []const u8 = "This is a template string";
    const query = server.Parser.query(IndexQuery, allocator, request);

    if (query != null) {
        value = try fmt.urlDecode(query.?.value orelse "default", allocator);
    }
    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("pages/resp.html", .{ .value = value }, heap);

    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

fn hxExec(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    var value: []const u8 = "This is a template string";
    const reqBody = try server.Parser.json(PostInput, allocator, request);

    // Get command from query parameter
    const shell = if (builtin.os.tag == .linux) "/bin/bash" else "/usr/local/bin/bash";

    // Execute shell command
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ shell, "-c", reqBody.request },
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Error executing command: {}", .{err});
        defer allocator.free(error_msg);
        value = error_msg;

        const heap = std.heap.page_allocator;
        const body = try fmt.renderTemplate("pages/resp.html", .{ .value = value }, heap);
        defer heap.free(body);
        try request.respond(body, .{ .status = .internal_server_error, .keep_alive = false });
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Use stdout if available, otherwise stderr
    value = if (result.stdout.len > 0) result.stdout else result.stderr;

    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("pages/resp.html", .{ .value = value }, heap);
    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

const DataResponse = struct {
    userId: i32,
    id: i32,
    title: []const u8,
    body: []const u8,
};

fn postEndpoint(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    pubCounter.lock.lock();
    pubCounter.value += 1;
    pubCounter.lock.unlock();
    const reqBody = try server.Parser.json(PostInput, allocator, request);
    const out = PostResponse{
        .message = "Hello from Zoi!",
        .endpoint = "",
        .counter = if (std.mem.eql(u8, reqBody.request, "counter")) pubCounter.value else std.time.timestamp(),
    };
    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("index.html", .{ .value = "hi" }, heap);
    defer heap.free(body);
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };
    try server.sendJson(allocator, request, out, .{ .status = .ok, .keep_alive = false, .extra_headers = headers });
}

const PubCounter = struct {
    value: i64,
    lock: std.Thread.Mutex,
};

var pubCounter = PubCounter{
    .value = 0,
    .lock = .{},
};

const PostResponse = struct {
    message: []const u8,
    endpoint: []const u8,
    counter: i64,
};

const PostInput = struct {
    request: []const u8,
};
