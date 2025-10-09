const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const r = @import("routes.zig");
const browser = @import("browser.zig");
const Foo = struct { bar: u1, foo: []const u8 };
const stdout = std.io.getStdOut().writer();
const sql = @import("sql.zig");
const ServerContext = struct {
    server: *server.Server,
    routes: std.ArrayList(server.Route),
};

fn runServerWrapper(context: ServerContext) void {
    context.server.runServer(.{ .routes = context.routes }) catch |err| {
        std.log.err("Server error: {}", .{err});
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    try sql.init(allocator);
    var settings = try Config.init("config.json", allocator);
    defer settings.deinit(allocator);
    var routes = std.ArrayList(server.Route){};
    try routes.appendSlice(allocator, r.routes);
    defer routes.deinit(allocator);
    var s = try server.Server.init(&settings, allocator);
    const context = ServerContext{
        .server = &s,
        .routes = routes,
    };

    const worker = try std.Thread.spawn(.{}, browser.runBrowser, .{});
    const serverW = try std.Thread.spawn(.{}, runServerWrapper, .{context});

    worker.join();
    serverW.join();
}
