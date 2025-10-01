const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const fmt = @import("fmt.zig");
const stdout = std.io.getStdOut().writer();

pub const routes = &[_]server.Route{
    .{ .path = "/", .callback = index },
    .{ .path = "/home", .callback = index },
    .{ .path = "/", .method = .POST, .callback = postEndpoint },
    .{ .path = "/styles/*", .callback = server.static },
    .{ .path = "/scripts/*", .callback = server.static },
    .{ .path = "/scripts/*", .callback = server.static },
    .{ .path = "/_astro/*", .callback = server.static },
    .{ .path = "/fonts/*", .callback = server.static },

    .{ .path = "/api", .method = .GET, .callback = htmxEndpoint },
    .{ .path = "/api", .method = .POST, .callback = htmxEndpoint },
};

const IndexQuery = struct {
    value: ?[]const u8,
};
/// return index.html to the home route
fn index(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const value: []const u8 = "This string was rendered by the server";
    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("frontend/dist/index.html", .{ .value = value }, heap);

    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

fn preflight(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const value: []const u8 = "";
    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("frontend/dist/index.html", .{ .value = value }, heap);
    std.debug.print("got preflight", .{});
    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false, .extra_headers = &cors_headers });
}

const cors_headers = [_]std.http.Header{
    .{ .name = "Access-Control-Allow-Origin", .value = "*" }, // Or specify your frontend origin
    .{ .name = "Access-Control-Allow-Methods", .value = "GET, POST, PUT, DELETE, OPTIONS" },
    .{ .name = "Access-Control-Allow-Headers", .value = "Content-Type, Authorization" },
    .{ .name = "Access-Control-Max-Age", .value = "86400" }, // 24 hours
};

fn htmxEndpoint(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("\nHere at htmx", .{});

    const body: []const u8 = "This string was rendered by the server";
    std.debug.print("/n{s}", .{body});
    try request.respond(body, .{ .status = .ok, .keep_alive = false, .extra_headers = &cors_headers });
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
