//! bgfx Backend Example
//!
//! Demonstrates the bgfx backend with GLFW window management.
//! This example shows basic bgfx rendering with debug text.
//!
//! Prerequisites:
//! - GLFW for window creation
//! - bgfx for rendering

const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zglfw");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const gfx = @import("labelle");
const BgfxBackend = gfx.BgfxBackend;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

// macOS Cocoa bindings for app activation
const macos = if (builtin.os.tag == .macos) struct {
    const c = @cImport({
        @cInclude("objc/runtime.h");
        @cInclude("objc/message.h");
    });

    // objc_msgSend function pointer types
    const MsgSendFn = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque;
    const MsgSendBoolFn = *const fn (?*anyopaque, ?*anyopaque, bool) callconv(.c) void;
    const MsgSendVoidFn = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;

    fn activateApp() void {
        // Get NSApplication class
        const NSApplication = c.objc_getClass("NSApplication");
        if (NSApplication == null) return;

        // Get shared application instance
        const sel_sharedApplication = c.sel_registerName("sharedApplication");
        const msgSend: MsgSendFn = @ptrCast(&c.objc_msgSend);
        const app = msgSend(@ptrCast(NSApplication), sel_sharedApplication);
        if (app == null) return;

        // Activate ignoring other apps
        const sel_activate = c.sel_registerName("activateIgnoringOtherApps:");
        const msgSendBool: MsgSendBoolFn = @ptrCast(&c.objc_msgSend);
        msgSendBool(app, sel_activate, true);
    }

    fn makeWindowKeyAndFront(nswindow: ?*anyopaque) void {
        if (nswindow == null) return;

        const msgSendVoid: MsgSendVoidFn = @ptrCast(&c.objc_msgSend);

        // Make window key and order front
        const sel_makeKeyAndOrderFront = c.sel_registerName("makeKeyAndOrderFront:");
        msgSendVoid(nswindow, sel_makeKeyAndOrderFront);

        // Also try orderFrontRegardless for good measure
        const sel_orderFrontRegardless = c.sel_registerName("orderFrontRegardless");
        msgSendVoid(nswindow, sel_orderFrontRegardless);
    }

    fn setupMetalLayer(nswindow: ?*anyopaque) ?*anyopaque {
        if (nswindow == null) return null;

        const msgSend: MsgSendFn = @ptrCast(&c.objc_msgSend);
        const msgSendBool: MsgSendBoolFn = @ptrCast(&c.objc_msgSend);
        const msgSendId = @as(*const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void, @ptrCast(&c.objc_msgSend));

        // Get content view from NSWindow
        const sel_contentView = c.sel_registerName("contentView");
        const content_view = msgSend(nswindow, sel_contentView);
        if (content_view == null) return null;

        // Set wantsLayer = YES on content view (required for Metal)
        const sel_setWantsLayer = c.sel_registerName("setWantsLayer:");
        msgSendBool(content_view, sel_setWantsLayer, true);

        // Create CAMetalLayer
        const CAMetalLayer = c.objc_getClass("CAMetalLayer");
        if (CAMetalLayer == null) return null;

        const sel_alloc = c.sel_registerName("alloc");
        const sel_init = c.sel_registerName("init");
        const metal_layer_alloc = msgSend(@ptrCast(CAMetalLayer), sel_alloc);
        const metal_layer = msgSend(metal_layer_alloc, sel_init);
        if (metal_layer == null) return null;

        // Set layer on content view
        const sel_setLayer = c.sel_registerName("setLayer:");
        msgSendId(content_view, sel_setLayer, metal_layer);

        return metal_layer;
    }
} else struct {
    fn activateApp() void {}
    fn makeWindowKeyAndFront(_: ?*anyopaque) void {}
    fn setupMetalLayer(_: ?*anyopaque) ?*anyopaque {
        return null;
    }
};

pub fn main() !void {
    // On macOS, enable menubar for proper app behavior (must be set before init)
    if (builtin.os.tag == .macos) {
        zglfw.InitHint.set(.cocoa_menubar, true) catch {};
    }

    // Initialize GLFW
    zglfw.init() catch |err| {
        std.log.err("Failed to initialize GLFW: {}", .{err});
        return error.GlfwInitFailed;
    };
    defer zglfw.terminate();

    // Use NO_API for Metal/bgfx - don't create OpenGL context
    zglfw.windowHint(.client_api, .no_api);
    zglfw.windowHint(.decorated, true);
    zglfw.windowHint(.resizable, true);

    // Create window
    const window = zglfw.Window.create(
        @intCast(WIDTH),
        @intCast(HEIGHT),
        "bgfx Backend Example",
        null,
    ) catch |err| {
        std.log.err("Failed to create window: {}", .{err});
        return error.WindowCreationFailed;
    };
    defer window.destroy();

    // Get native window handle for bgfx
    const native_window_handle = getNativeWindowHandle(window);
    const native_display_handle = getNativeDisplayHandle();

    std.log.info("Native window handle: {?}", .{native_window_handle});
    std.log.info("Window size: {}x{}", .{window.getSize()[0], window.getSize()[1]});

    if (native_window_handle == null) {
        std.log.err("Failed to get native window handle for platform: {}", .{builtin.os.tag});
        return error.NativeWindowHandleFailed;
    }

    // On macOS, create CAMetalLayer and pass it to bgfx (instead of NSWindow)
    const bgfx_nwh = if (builtin.os.tag == .macos)
        macos.setupMetalLayer(native_window_handle) orelse native_window_handle
    else
        native_window_handle;

    // Set screen size before init
    BgfxBackend.setScreenSize(@intCast(WIDTH), @intCast(HEIGHT));

    // Initialize bgfx using BgfxBackend (includes debugdraw)
    BgfxBackend.initBgfx(bgfx_nwh, native_display_handle) catch |err| {
        std.log.err("Failed to initialize bgfx backend: {}", .{err});
        return error.BgfxInitFailed;
    };
    defer BgfxBackend.closeWindow();

    std.log.info("bgfx initialized successfully!", .{});
    std.log.info("Renderer: {s}", .{bgfx.getRendererName(bgfx.getRendererType())});

    // Activate app and bring window to front on macOS
    if (builtin.os.tag == .macos) {
        macos.activateApp();
        macos.makeWindowKeyAndFront(native_window_handle);
    }

    std.log.info("Window should now be visible. Press ESC to close.", .{});

    // Main loop
    var frame_count: u32 = 0;

    while (!window.shouldClose()) {
        // Handle input
        zglfw.pollEvents();

        // Check for escape key (check both press states)
        const escape_state = window.getKey(.escape);
        if (escape_state == .press or escape_state == .repeat) {
            std.log.info("Escape pressed, closing window", .{});
            window.setShouldClose(true);
            break;
        }

        // Begin frame with debugdraw encoder
        BgfxBackend.beginDrawing();

        // Set background color (cycling)
        const t: f32 = @as(f32, @floatFromInt(frame_count)) / 60.0;
        const bg_r: u8 = @intFromFloat(40 + 20 * @sin(t));
        const bg_g: u8 = @intFromFloat(40 + 20 * @sin(t + 2.1));
        const bg_b: u8 = @intFromFloat(50 + 20 * @sin(t + 4.2));
        BgfxBackend.clearBackground(BgfxBackend.color(bg_r, bg_g, bg_b, 255));

        // Draw shapes using BgfxBackend
        // Filled rectangle
        BgfxBackend.drawRectangleV(50, 50, 150, 100, BgfxBackend.red);

        // Rectangle outline
        BgfxBackend.drawRectangleLinesV(250, 50, 150, 100, BgfxBackend.green);

        // Filled circle
        BgfxBackend.drawCircle(125, 300, 60, BgfxBackend.blue);

        // Circle outline
        BgfxBackend.drawCircleLines(325, 300, 60, BgfxBackend.yellow);

        // Triangle
        BgfxBackend.drawTriangle(500, 150, 550, 50, 600, 150, BgfxBackend.purple);

        // Triangle outline
        BgfxBackend.drawTriangleLines(650, 150, 700, 50, 750, 150, BgfxBackend.orange);

        // Lines
        BgfxBackend.drawLine(450, 250, 550, 350, BgfxBackend.white);
        BgfxBackend.drawLineEx(600, 250, 700, 350, 5.0, BgfxBackend.pink);

        // Polygon (hexagon)
        BgfxBackend.drawPoly(550, 480, 6, 50, 0, BgfxBackend.magenta);

        // Polygon outline (pentagon)
        BgfxBackend.drawPolyLines(700, 480, 5, 50, 0, BgfxBackend.light_gray);

        // End frame
        BgfxBackend.endDrawing();

        frame_count += 1;
    }

    std.log.info("Example completed. Total frames: {}", .{frame_count});
}

fn getNativeWindowHandle(window: *zglfw.Window) ?*anyopaque {
    if (builtin.os.tag == .macos) {
        return zglfw.getCocoaWindow(window);
    } else if (builtin.os.tag == .linux) {
        // For X11 - convert u32 to pointer
        const x11_window = zglfw.getX11Window(window);
        return @ptrFromInt(x11_window);
    } else if (builtin.os.tag == .windows) {
        if (zglfw.getWin32Window(window)) |hwnd| {
            return @ptrCast(hwnd);
        }
    }
    return null;
}

fn getNativeDisplayHandle() ?*anyopaque {
    if (builtin.os.tag == .linux) {
        return zglfw.getX11Display();
    }
    return null;
}
