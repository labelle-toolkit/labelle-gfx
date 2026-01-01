//! bgfx Backend Example
//!
//! Demonstrates the bgfx backend with GLFW window management.
//! This example shows basic bgfx rendering including:
//! - Shape primitives (rectangle, circle, triangle, line, polygon)
//! - Sprite/texture rendering with procedural textures
//! - Camera controls (pan, zoom, rotation)
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
        zglfw.InitHint.set(.cocoa_menubar, true) catch |err| {
            std.log.warn("Failed to set cocoa_menubar hint: {}", .{err});
        };
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
    const bgfx_nwh = if (builtin.os.tag == .macos) blk: {
        const metal_layer = macos.setupMetalLayer(native_window_handle);
        if (metal_layer == null) {
            std.log.warn("Failed to create CAMetalLayer, falling back to NSWindow handle", .{});
        }
        break :blk metal_layer orelse native_window_handle;
    } else native_window_handle;

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

    // Load sprite textures from fixtures
    const coin_texture = BgfxBackend.loadTexture("fixtures/sprites/items/coin.png") catch |err| {
        std.log.err("Failed to load coin texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer BgfxBackend.unloadTexture(coin_texture);

    const gem_texture = BgfxBackend.loadTexture("fixtures/sprites/items/gem.png") catch |err| {
        std.log.err("Failed to load gem texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer BgfxBackend.unloadTexture(gem_texture);

    const heart_texture = BgfxBackend.loadTexture("fixtures/sprites/items/heart.png") catch |err| {
        std.log.err("Failed to load heart texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer BgfxBackend.unloadTexture(heart_texture);

    const key_texture = BgfxBackend.loadTexture("fixtures/sprites/items/key.png") catch |err| {
        std.log.err("Failed to load key texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer BgfxBackend.unloadTexture(key_texture);

    const potion_texture = BgfxBackend.loadTexture("fixtures/sprites/items/potion.png") catch |err| {
        std.log.err("Failed to load potion texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer BgfxBackend.unloadTexture(potion_texture);

    const sword_texture = BgfxBackend.loadTexture("fixtures/sprites/items/sword.png") catch |err| {
        std.log.err("Failed to load sword texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer BgfxBackend.unloadTexture(sword_texture);

    const texture_count = 6; // coin, gem, heart, key, potion, sword
    std.log.info("Loaded {} sprite textures from fixtures", .{texture_count});

    // Create a solid test texture to verify rendering pipeline
    const test_texture = BgfxBackend.createSolidTexture(24, 24, BgfxBackend.color(255, 128, 0, 255)) catch |err| {
        std.log.err("Failed to create test texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer BgfxBackend.unloadTexture(test_texture);
    std.log.info("Created solid test texture for comparison", .{});

    // Activate app and bring window to front on macOS
    if (builtin.os.tag == .macos) {
        macos.activateApp();
        macos.makeWindowKeyAndFront(native_window_handle);
    }

    std.log.info("Window should now be visible. Press ESC to close.", .{});
    std.log.info("Controls: Arrow keys = pan, +/- = zoom, R = rotate, Space = reset", .{});

    // Camera state
    var camera = BgfxBackend.Camera2D{
        .offset = .{ .x = @floatFromInt(WIDTH) / 2.0, .y = @floatFromInt(HEIGHT) / 2.0 },
        .target = .{ .x = @floatFromInt(WIDTH) / 2.0, .y = @floatFromInt(HEIGHT) / 2.0 },
        .rotation = 0,
        .zoom = 1.0,
    };

    // Main loop
    var frame_count: u32 = 0;
    const camera_speed: f32 = 5.0;
    var sprite_rotation: f32 = 0.0;

    while (!window.shouldClose()) {
        // Handle input
        zglfw.pollEvents();

        // Check for escape key
        const escape_state = window.getKey(.escape);
        if (escape_state == .press or escape_state == .repeat) {
            std.log.info("Escape pressed, closing window", .{});
            window.setShouldClose(true);
            break;
        }

        // Camera controls
        if (window.getKey(.left) == .press or window.getKey(.left) == .repeat) {
            camera.target.x -= camera_speed / camera.zoom;
        }
        if (window.getKey(.right) == .press or window.getKey(.right) == .repeat) {
            camera.target.x += camera_speed / camera.zoom;
        }
        if (window.getKey(.up) == .press or window.getKey(.up) == .repeat) {
            camera.target.y -= camera_speed / camera.zoom;
        }
        if (window.getKey(.down) == .press or window.getKey(.down) == .repeat) {
            camera.target.y += camera_speed / camera.zoom;
        }
        if (window.getKey(.equal) == .press or window.getKey(.equal) == .repeat) {
            camera.zoom = @min(camera.zoom * 1.02, 10.0);
        }
        if (window.getKey(.minus) == .press or window.getKey(.minus) == .repeat) {
            camera.zoom = @max(camera.zoom / 1.02, 0.1);
        }
        if (window.getKey(.r) == .press or window.getKey(.r) == .repeat) {
            camera.rotation += 1.0;
        }
        if (window.getKey(.space) == .press) {
            // Reset camera
            camera.target = .{ .x = @as(f32, WIDTH) / 2.0, .y = @as(f32, HEIGHT) / 2.0 };
            camera.zoom = 1.0;
            camera.rotation = 0;
        }

        // Begin frame with debugdraw encoder
        BgfxBackend.beginDrawing();

        // Set background color (dark gray)
        BgfxBackend.clearBackground(BgfxBackend.color(40, 40, 50, 255));

        // Begin camera mode
        BgfxBackend.beginMode2D(camera);

        // Update sprite rotation
        sprite_rotation += 0.5;

        // ============================================
        // SPRITE RENDERING DEMO
        // ============================================

        // Helper to get texture dimensions as floats
        const coin_w: f32 = @floatFromInt(coin_texture.width);
        const coin_h: f32 = @floatFromInt(coin_texture.height);
        const gem_w: f32 = @floatFromInt(gem_texture.width);
        const gem_h: f32 = @floatFromInt(gem_texture.height);
        const heart_w: f32 = @floatFromInt(heart_texture.width);
        const heart_h: f32 = @floatFromInt(heart_texture.height);
        const key_w: f32 = @floatFromInt(key_texture.width);
        const key_h: f32 = @floatFromInt(key_texture.height);
        const potion_w: f32 = @floatFromInt(potion_texture.width);
        const potion_h: f32 = @floatFromInt(potion_texture.height);
        const sword_w: f32 = @floatFromInt(sword_texture.width);
        const sword_h: f32 = @floatFromInt(sword_texture.height);

        const sprite_scale: f32 = 3.0;

        // Draw coin - static sprite
        BgfxBackend.drawTexturePro(
            coin_texture,
            .{ .x = 0, .y = 0, .width = coin_w, .height = coin_h },
            .{ .x = 50, .y = 420, .width = coin_w * sprite_scale, .height = coin_h * sprite_scale },
            .{ .x = 0, .y = 0 },
            0,
            BgfxBackend.white,
        );

        // Draw gem - rotating sprite
        BgfxBackend.drawTexturePro(
            gem_texture,
            .{ .x = 0, .y = 0, .width = gem_w, .height = gem_h },
            .{ .x = 150, .y = 450, .width = gem_w * sprite_scale, .height = gem_h * sprite_scale },
            .{ .x = gem_w * sprite_scale / 2, .y = gem_h * sprite_scale / 2 },
            sprite_rotation,
            BgfxBackend.white,
        );

        // Draw heart - pulsing (using scale from rotation)
        const pulse_scale = 2.5 + @sin(sprite_rotation * 0.1) * 0.5;
        BgfxBackend.drawTexturePro(
            heart_texture,
            .{ .x = 0, .y = 0, .width = heart_w, .height = heart_h },
            .{ .x = 280, .y = 450, .width = heart_w * pulse_scale, .height = heart_h * pulse_scale },
            .{ .x = heart_w * pulse_scale / 2, .y = heart_h * pulse_scale / 2 },
            0,
            BgfxBackend.color(255, 100, 100, 255), // red tint
        );

        // Draw key - rotating opposite direction
        BgfxBackend.drawTexturePro(
            key_texture,
            .{ .x = 0, .y = 0, .width = key_w, .height = key_h },
            .{ .x = 400, .y = 450, .width = key_w * sprite_scale, .height = key_h * sprite_scale },
            .{ .x = key_w * sprite_scale / 2, .y = key_h * sprite_scale / 2 },
            -sprite_rotation * 0.5,
            BgfxBackend.yellow,
        );

        // Draw potion - with green tint
        BgfxBackend.drawTexturePro(
            potion_texture,
            .{ .x = 0, .y = 0, .width = potion_w, .height = potion_h },
            .{ .x = 520, .y = 420, .width = potion_w * sprite_scale, .height = potion_h * sprite_scale },
            .{ .x = 0, .y = 0 },
            0,
            BgfxBackend.color(100, 255, 100, 255),
        );

        // Draw sword - rotating around handle
        BgfxBackend.drawTexturePro(
            sword_texture,
            .{ .x = 0, .y = 0, .width = sword_w, .height = sword_h },
            .{ .x = 680, .y = 500, .width = sword_w * sprite_scale, .height = sword_h * sprite_scale },
            .{ .x = sword_w * sprite_scale * 0.2, .y = sword_h * sprite_scale * 0.8 }, // pivot near handle
            sprite_rotation * 0.3,
            BgfxBackend.white,
        );

        // Draw test texture (solid orange square) - to verify rendering pipeline
        const test_w: f32 = @floatFromInt(test_texture.width);
        const test_h: f32 = @floatFromInt(test_texture.height);
        BgfxBackend.drawTexturePro(
            test_texture,
            .{ .x = 0, .y = 0, .width = test_w, .height = test_h },
            .{ .x = 750, .y = 420, .width = test_w * sprite_scale, .height = test_h * sprite_scale },
            .{ .x = 0, .y = 0 },
            0,
            BgfxBackend.white,
        );

        // ============================================
        // SHAPE RENDERING DEMO
        // ============================================

        // Draw shapes using BgfxBackend (in world space)
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

        // Grid lines (to see camera movement)
        var x: f32 = 0;
        while (x <= @as(f32, WIDTH)) : (x += 100) {
            BgfxBackend.drawLine(x, 0, x, @floatFromInt(HEIGHT), BgfxBackend.dark_gray);
        }
        var y: f32 = 0;
        while (y <= @as(f32, HEIGHT)) : (y += 100) {
            BgfxBackend.drawLine(0, y, @floatFromInt(WIDTH), y, BgfxBackend.dark_gray);
        }

        // End camera mode
        BgfxBackend.endMode2D();

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
