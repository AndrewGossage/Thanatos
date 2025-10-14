const std = @import("std");
const server = @import("server.zig");
pub var s: *server.Server = undefined;
// Import C headers directly
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit2/webkit2.h");
});
pub var lock: std.Thread.Mutex = .{};

// Signal handler for window destruction
fn onDestroy(widget: ?*c.GtkWidget, user_data: ?*anyopaque) callconv(.c) void {
    _ = widget;
    _ = user_data;

    c.gtk_main_quit();
    s.triggerClose();
}

// Signal handler for web view close
fn onWebViewClose(web_view: ?*c.WebKitWebView, window: ?*anyopaque) callconv(.c) c.gboolean {
    _ = web_view;
    const main_window: ?*c.GtkWidget = @ptrCast(@alignCast(window));
    c.gtk_widget_destroy(main_window);
    return if (c.TRUE) 1 else 0;
}

pub fn runBrowser(serve: *server.Server) !void {
    // Initialize GTK
    _ = c.gtk_init(null, null);
    var serve2 = serve;
    serve2 = serve2;
    s = serve2;
    // Create the main window
    const main_window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
    c.gtk_window_set_default_size(@ptrCast(main_window), 1024, 768);
    c.gtk_window_set_title(@ptrCast(main_window), "WebKitGTK Local Server Browser");

    // Create the WebKit web view
    const web_view = c.webkit_web_view_new();

    // Add the web view to the window
    c.gtk_container_add(@ptrCast(main_window), web_view);

    // Connect signal handlers using g_signal_connect
    _ = c.g_signal_connect_data(main_window, "destroy", @ptrCast(&onDestroy), null, null, 0);

    _ = c.g_signal_connect_data(web_view, "close", @ptrCast(&onWebViewClose), main_window, null, 0);

    // Load your local server (change the URL as needed)
    c.webkit_web_view_load_uri(@ptrCast(web_view), "http://localhost:8081");

    // Show all widgets
    c.gtk_widget_show_all(main_window);

    // Start the GTK main loop
    c.gtk_main();
}
