//! Window Management
//!
//! GLFW window creation, WebGPU initialisation, surface creation from
//! platform-specific handles, and window lifecycle functions.

const std = @import("std");
const builtin = @import("builtin");
const wgpu = @import("wgpu");
const zglfw = @import("zglfw");

const backend_mod = @import("../backend.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const vertex = @import("vertex.zig");
const pipeline = @import("pipeline.zig");

// Platform-specific imports for Metal layer creation
const objc = if (builtin.os.tag == .macos) struct {
    const c = @cImport({
        @cInclude("objc/message.h");
        @cInclude("objc/runtime.h");
    });

    pub inline fn getClass(name: [*:0]const u8) ?*anyopaque {
        return c.objc_getClass(name);
    }

    pub inline fn sel(name: [*:0]const u8) ?*anyopaque {
        return @ptrCast(c.sel_registerName(name));
    }

    pub inline fn msgSend(target: ?*anyopaque, selector: ?*anyopaque) ?*anyopaque {
        const func = @as(*const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque, @ptrCast(&c.objc_msgSend));
        return func(target, selector);
    }

    pub inline fn msgSendBool(target: ?*anyopaque, selector: ?*anyopaque, value: bool) void {
        const func = @as(*const fn (?*anyopaque, ?*anyopaque, u8) callconv(.c) void, @ptrCast(&c.objc_msgSend));
        func(target, selector, if (value) 1 else 0);
    }

    pub inline fn msgSendPtr(target: ?*anyopaque, selector: ?*anyopaque, arg: ?*anyopaque) void {
        const func = @as(*const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void, @ptrCast(&c.objc_msgSend));
        func(target, selector, arg);
    }
} else struct {};

/// Initializes a GLFW window and the WebGPU backend.
/// This function assumes ownership of the GLFW lifecycle. It will call `zglfw.init()`
/// and `closeWindow()` will call `zglfw.terminate()`.
/// If you want to manage the GLFW window and its lifecycle manually,
/// create a window yourself and then call `initWgpuNative()`.
pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) !void {
    // Initialize GLFW
    zglfw.init() catch |err| {
        std.log.err("[wgpu_native] Failed to initialize GLFW: {}", .{err});
        return error.GlfwInitFailed;
    };

    // Apply window hints based on config flags
    if (state.config_flags.window_hidden) {
        zglfw.windowHint(.visible, false);
    }
    zglfw.windowHint(.resizable, state.config_flags.window_resizable);

    // Don't use OpenGL - we're using WebGPU
    zglfw.windowHint(.client_api, .no_api);

    // Create GLFW window
    const window = zglfw.createWindow(
        width,
        height,
        std.mem.span(title),
        null,
    ) catch |err| {
        std.log.err("[wgpu_native] Failed to create GLFW window: {}", .{err});
        zglfw.terminate();
        return error.WindowCreationFailed;
    };

    state.glfw_window = window;
    state.owns_window = true;

    // Initialize WebGPU with the created window
    // Use pre-configured allocator if set, otherwise fall back to page_allocator
    const alloc = state.allocator orelse std.heap.page_allocator;
    initWgpuNative(alloc, window) catch |err| {
        std.log.err("[wgpu_native] Failed to initialize WebGPU: {}", .{err});
        window.destroy();
        state.glfw_window = null;
        state.owns_window = false;
        zglfw.terminate();
        return err;
    };

    std.log.info("[wgpu_native] Window and WebGPU initialized ({}x{})", .{ width, height });
}

pub fn initWgpuNative(alloc: std.mem.Allocator, window_handle: *zglfw.Window) !void {
    state.allocator = alloc;
    state.glfw_window = window_handle;

    // Get framebuffer size
    const fb_size = window_handle.getFramebufferSize();
    state.screen_width = @intCast(fb_size[0]);
    state.screen_height = @intCast(fb_size[1]);

    // 1. Create WebGPU instance
    state.instance = wgpu.Instance.create(&.{
        .features = .{
            .timed_wait_any_enable = 0, // WGPUBool false
            .timed_wait_any_max_count = 0,
        },
    }) orelse return error.InstanceCreationFailed;
    errdefer {
        state.instance.?.release();
        state.instance = null;
    }

    // 2. Create surface from GLFW window
    state.surface = try createSurfaceFromGLFW(window_handle);
    errdefer {
        state.surface.?.release();
        state.surface = null;
    }

    // 3. Request adapter
    const adapter_opts = wgpu.RequestAdapterOptions{
        .compatible_surface = state.surface,
        .power_preference = .high_performance,
    };

    // Use synchronous adapter request
    const adapter_response = state.instance.?.requestAdapterSync(&adapter_opts, state.SYNC_TIMEOUT_NS);
    if (adapter_response.status != .success) {
        std.log.err("Failed to request adapter: {?s}", .{adapter_response.message});
        return error.AdapterRequestFailed;
    }
    state.adapter = adapter_response.adapter;
    errdefer {
        state.adapter.?.release();
        state.adapter = null;
    }

    // 4. Request device
    const device_descriptor = wgpu.DeviceDescriptor{
        .label = wgpu.StringView.fromSlice("Main Device"),
        .required_limits = null,
    };

    const device_response = state.adapter.?.requestDeviceSync(state.instance.?, &device_descriptor, state.SYNC_TIMEOUT_NS);
    if (device_response.status != .success) {
        std.log.err("Failed to request device: {?s}", .{device_response.message});
        return error.DeviceRequestFailed;
    }
    state.device = device_response.device;
    errdefer {
        state.device.?.release();
        state.device = null;
    }

    // 5. Get queue
    state.queue = state.device.?.getQueue();
    errdefer {
        state.queue.?.release();
        state.queue = null;
    }

    // 6. Configure surface
    var surface_caps: wgpu.SurfaceCapabilities = undefined;
    const caps_status = state.surface.?.getCapabilities(state.adapter.?, &surface_caps);
    if (caps_status != .success) {
        return error.SurfaceCapabilitiesFailed;
    }
    defer surface_caps.freeMembers();

    state.surface_config = .{
        .device = state.device.?,
        .format = surface_caps.formats[0], // Use first supported format
        .usage = wgpu.TextureUsages.render_attachment,
        .width = @intCast(state.screen_width),
        .height = @intCast(state.screen_height),
        .present_mode = .fifo, // VSync
        .alpha_mode = surface_caps.alpha_modes[0],
    };
    state.surface.?.configure(&state.surface_config.?);

    // 7. Initialize rendering pipelines
    try pipeline.initPipelines();

    // 8. Initialize batching systems
    state.shape_batch = vertex.ShapeBatch.init();
    state.sprite_batch = vertex.SpriteBatch.init();
    state.sprite_draw_calls = .{};

    // 9. Initialize reusable GPU buffers
    const initial_shape_vertex_capacity = 1024;
    const initial_shape_index_capacity = 2048;
    const initial_sprite_vertex_capacity = 512;
    const initial_sprite_index_capacity = 1024;

    state.shape_vertex_buffer = state.device.?.createBuffer(&.{
        .size = initial_shape_vertex_capacity * @sizeOf(vertex.ColorVertex),
        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
        .mapped_at_creation = 0,
    });
    state.shape_vertex_capacity = initial_shape_vertex_capacity;

    state.shape_index_buffer = state.device.?.createBuffer(&.{
        .size = initial_shape_index_capacity * @sizeOf(u32),
        .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
        .mapped_at_creation = 0,
    });
    state.shape_index_capacity = initial_shape_index_capacity;

    state.sprite_vertex_buffer = state.device.?.createBuffer(&.{
        .size = initial_sprite_vertex_capacity * @sizeOf(vertex.SpriteVertex),
        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
        .mapped_at_creation = 0,
    });
    state.sprite_vertex_capacity = initial_sprite_vertex_capacity;

    state.sprite_index_buffer = state.device.?.createBuffer(&.{
        .size = initial_sprite_index_capacity * @sizeOf(u32),
        .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
        .mapped_at_creation = 0,
    });
    state.sprite_index_capacity = initial_sprite_index_capacity;

    // Initialize bind group cache
    state.sprite_bind_group_cache = std.AutoHashMap(usize, *wgpu.BindGroup).init(alloc);

    std.log.info("[wgpu_native] Initialized with {}x{} framebuffer", .{ state.screen_width, state.screen_height });
}

fn createSurfaceFromGLFW(window_handle: *zglfw.Window) !*wgpu.Surface {
    const inst = state.instance orelse return error.NoInstance;

    // Get platform-specific window handle and create surface using helper functions
    if (builtin.os.tag == .macos) {
        const ns_window = zglfw.getCocoaWindow(window_handle);
        if (ns_window) |win| {
            // Get the content view from the NSWindow
            const content_view = objc.msgSend(win, objc.sel("contentView")) orelse return error.NoContentView;

            // Get the CAMetalLayer class
            const metal_layer_class = objc.getClass("CAMetalLayer") orelse return error.NoMetalLayerClass;

            // Allocate and initialize a new CAMetalLayer: [[CAMetalLayer alloc] init]
            const metal_layer_alloc = objc.msgSend(metal_layer_class, objc.sel("alloc")) orelse return error.MetalLayerAllocFailed;
            const metal_layer = objc.msgSend(metal_layer_alloc, objc.sel("init")) orelse return error.MetalLayerInitFailed;

            // Set wantsLayer to YES first
            objc.msgSendBool(content_view, objc.sel("setWantsLayer:"), true);

            // Set the layer on the content view
            objc.msgSendPtr(content_view, objc.sel("setLayer:"), metal_layer);

            const descriptor = wgpu.surfaceDescriptorFromMetalLayer(.{
                .layer = metal_layer,
            });
            return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
        }
    } else if (builtin.os.tag == .linux) {
        // Try Wayland first, then X11
        if (zglfw.getWaylandDisplay(window_handle)) |display| {
            if (zglfw.getWaylandWindow(window_handle)) |wl_surface| {
                const descriptor = wgpu.surfaceDescriptorFromWaylandSurface(.{
                    .display = display,
                    .surface = wl_surface,
                });
                return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
            }
        }

        if (zglfw.getX11Display(window_handle)) |display| {
            if (zglfw.getX11Window(window_handle)) |x11_window| {
                const descriptor = wgpu.surfaceDescriptorFromXlibWindow(.{
                    .display = display,
                    .window = @intCast(x11_window),
                });
                return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
            }
        }
    } else if (builtin.os.tag == .windows) {
        const hwnd = zglfw.getWin32Window(window_handle);
        if (hwnd) |win| {
            const hinstance = @import("std").os.windows.kernel32.GetModuleHandleW(null);
            const descriptor = wgpu.surfaceDescriptorFromWindowsHWND(.{
                .hinstance = hinstance,
                .hwnd = win,
            });
            return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
        }
    }

    return error.UnsupportedPlatform;
}

pub fn closeWindow() void {
    std.log.info("[wgpu_native] Cleaning up resources...", .{});

    // Clear GUI render callback
    state.gui_render_callback = null;

    // Cleanup batches
    if (state.shape_batch) |*batch| {
        batch.deinit(state.allocator.?);
        state.shape_batch = null;
    }
    if (state.sprite_batch) |*batch| {
        batch.deinit(state.allocator.?);
        state.sprite_batch = null;
    }
    if (state.sprite_draw_calls) |*calls| {
        calls.deinit(state.allocator.?);
        state.sprite_draw_calls = null;
    }

    // Release pipelines
    if (state.shape_pipeline) |p| {
        p.release();
        state.shape_pipeline = null;
    }
    if (state.sprite_pipeline) |p| {
        p.release();
        state.sprite_pipeline = null;
    }

    // Release bind groups and layouts
    if (state.shape_bind_group) |bg| {
        bg.release();
        state.shape_bind_group = null;
    }
    if (state.shape_bind_group_layout) |layout| {
        layout.release();
        state.shape_bind_group_layout = null;
    }
    if (state.sprite_bind_group_layout) |layout| {
        layout.release();
        state.sprite_bind_group_layout = null;
    }

    // Release uniform buffer
    if (state.uniform_buffer) |buf| {
        buf.release();
        state.uniform_buffer = null;
    }

    // Release reusable GPU buffers
    if (state.shape_vertex_buffer) |buf| {
        buf.release();
        state.shape_vertex_buffer = null;
    }
    if (state.shape_index_buffer) |buf| {
        buf.release();
        state.shape_index_buffer = null;
    }
    if (state.sprite_vertex_buffer) |buf| {
        buf.release();
        state.sprite_vertex_buffer = null;
    }
    if (state.sprite_index_buffer) |buf| {
        buf.release();
        state.sprite_index_buffer = null;
    }

    // Release texture sampler
    if (state.texture_sampler) |sampler| {
        sampler.release();
        state.texture_sampler = null;
    }

    // Release cached sprite bind groups
    if (state.sprite_bind_group_cache) |*cache| {
        var iter = cache.valueIterator();
        while (iter.next()) |bind_group_ptr| {
            bind_group_ptr.*.release();
        }
        cache.deinit();
        state.sprite_bind_group_cache = null;
    }

    // Release surface (must be released before adapter)
    if (state.surface) |surf| {
        surf.release();
        state.surface = null;
    }

    // Release queue
    if (state.queue) |q| {
        q.release();
        state.queue = null;
    }

    // Release device
    if (state.device) |dev| {
        dev.release();
        state.device = null;
    }

    // Release adapter
    if (state.adapter) |adp| {
        adp.release();
        state.adapter = null;
    }

    // Release instance (must be last WebGPU resource)
    if (state.instance) |inst| {
        inst.release();
        state.instance = null;
    }

    // Destroy GLFW window and terminate if we created it
    if (state.owns_window) {
        if (state.glfw_window) |w| {
            w.destroy();
        }
        zglfw.terminate();
        state.owns_window = false;
    }
    state.glfw_window = null;

    std.log.info("[wgpu_native] Cleanup complete", .{});
}

pub fn windowShouldClose() bool {
    if (state.glfw_window) |w| {
        return w.shouldClose();
    }
    return true; // No window = should close
}

pub fn setTargetFPS(fps: i32) void {
    _ = fps;
    // Not needed - GLFW handles this
}

pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
    state.config_flags = flags;
}
