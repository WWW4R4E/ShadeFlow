const std = @import("std");

const win32 = @import("win32").everything;

const Engine = @import("engine/core/Engine.zig").Engine;
const Vertex = @import("engine/core/Engine.zig").Vertex;
const Window = @import("engine/optional/Window.zig").Window;
const Renderer = @import("engine/renderer/Renderer.zig").Renderer;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

// 日志级别枚举(对齐c#)
pub const LogLevel = enum(c_int) {
    Debug = 0,
    Info = 1,
    Warning = 2,
    Error = 3,
};

// 全局日志回调函数变量
var log_callback: ?*const anyopaque = null;

// 定义日志回调函数指针类型
const LogCallbackPtr = *const fn (level: c_int, message: [*c]const u8) callconv(.c) void;

// 引擎实例的全局存储
var engine_instance: ?*Engine = null;

// 日志输出
pub fn log(level_enum: LogLevel, comptime format: []const u8, args: anytype) void {
    var level: c_int = undefined;
    switch (level_enum) {
        .Debug => level = 0,
        .Info => level = 1,
        .Warning => level = 2,
        .Error => level = 3,
    }

    std.debug.print(format, args);

    if (log_callback) |callback_ptr| {
        var buffer: [512]u8 = undefined;
        const message = std.fmt.bufPrint(buffer[0..], format, args) catch |err| {
            std.debug.print("Failed to format log message: {}", .{err});
            return;
        };

        buffer[message.len] = 0;

        const callback = @as(LogCallbackPtr, @ptrCast(callback_ptr));
        callback(level, &buffer[0]);
    }
}

// 创建引擎实例(用于WinUI 3 Composition模式)
export fn ShadeFlow_CreateEngineForComposition(
    width: u32,
    height: u32,
) bool {
    log(LogLevel.Info, "[ShadeFlow_CreateEngineForComposition] Creating engine with size: {}x{}\n", .{ width, height });

    // 如果引擎已经初始化，释放旧实例
    if (engine_instance) |engine| {
        log(LogLevel.Info, "[ShadeFlow_CreateEngineForComposition] Releasing existing engine instance\n", .{});
        engine.deinit();
        engine_instance = null;
    }

    // 使用Composition模式初始化引擎
    engine_instance = Engine.initForComposition(allocator, width, height) catch |err| {
        log(LogLevel.Error, "[ShadeFlow_CreateEngineForComposition] Failed to create engine: {}\n", .{err});
        return false;
    };

    log(LogLevel.Info, "[ShadeFlow_CreateEngineForComposition] Engine created successfully\n", .{});
    return true;
}

// 获取交换链指针
export fn ShadeFlow_GetSwapChain() ?*anyopaque {
    if (engine_instance) |engine| {
        if (engine.renderer) |*renderer| {
            const swap_chain_ptr = @as(*anyopaque, @ptrCast(renderer.getSwapChain().handle));
            log(LogLevel.Debug, "[ShadeFlow_GetSwapChain] Swap chain pointer: {*}\n", .{swap_chain_ptr});
            return swap_chain_ptr;
        }
    }
    log(LogLevel.Error, "[ShadeFlow_GetSwapChain] Engine not initialized or no swap chain available\n", .{});
    return @ptrFromInt(0);
}

// 调整渲染器大小
export fn ShadeFlow_ResizeRenderer(width: u32, height: u32) bool {
    log(LogLevel.Debug, "[ShadeFlow_ResizeRenderer] Resizing renderer to: {}x{}\n", .{ width, height });

    if (engine_instance) |engine| {
        if (engine.renderer) |*renderer| {
            renderer.resize(width, height) catch |err| {
                log(LogLevel.Error, "[ShadeFlow_ResizeRenderer] Failed to resize renderer: {}\n", .{err});
                return false;
            };
            return true;
        }
    }
    log(LogLevel.Error, "[ShadeFlow_ResizeRenderer] Engine not initialized\n", .{});
    return false;
}

// 渲染
export fn ShadeFlow_RenderFrame() bool {
    // log(LogLevel.Debug, "[ShadeFlow_RenderFrame] Starting frame render\n", .{});

    if (engine_instance) |engine| {
        engine.render();
    }
    // log(LogLevel.Error, "[ShadeFlow_RenderFrame] Engine not initialized\n", .{});
    return false;
}

// 添加三角形渲染对象
export fn ShadeFlow_AddTriangleObject(
    vertex_shader_path_ptr: [*:0]const u8,
    pixel_shader_path_ptr: [*:0]const u8,
) bool {
    log(LogLevel.Debug, "[ShadeFlow_AddTriangleObject] Adding triangle object\n", .{});

    if (engine_instance) |engine| {
        // 将C字符串转换为Zig切片
        const vertex_shader_path = std.mem.sliceTo(vertex_shader_path_ptr, 0);
        const pixel_shader_path = std.mem.sliceTo(pixel_shader_path_ptr, 0);

        log(LogLevel.Debug, "[ShadeFlow_AddTriangleObject] Vertex shader path: {s}, Pixel shader path: {s}\n", .{ vertex_shader_path, pixel_shader_path });

        const triangle_vertices = [_]Vertex{
            Vertex{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },
            Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } },
            Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } },
        };
        engine.addRenderObject(&triangle_vertices, vertex_shader_path, pixel_shader_path) catch |err| {
            log(LogLevel.Error, "[ShadeFlow_AddTriangleObject] Failed to add render object: {}\n", .{err});
            return false;
        };

        log(LogLevel.Info, "[ShadeFlow_AddTriangleObject] Triangle object added successfully\n", .{});
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddTriangleObject] Engine not initialized\n", .{});
    return false;
}

// 添加四边形渲染对象
export fn ShadeFlow_AddQuadObject(
    vertex_shader_path_ptr: [*:0]const u8,
    pixel_shader_path_ptr: [*:0]const u8,
) bool {
    log(LogLevel.Debug, "[ShadeFlow_AddQuadObject] Adding quad object\n", .{});

    if (engine_instance) |engine| {
        const vertex_shader_path = std.mem.sliceTo(vertex_shader_path_ptr, 0);
        const pixel_shader_path = std.mem.sliceTo(pixel_shader_path_ptr, 0);

        log(LogLevel.Debug, "[ShadeFlow_AddQuadObject] Vertex shader path: {s}, Pixel shader path: {s}\n", .{ vertex_shader_path, pixel_shader_path });

        const quad_vertices = [_]Vertex{
            Vertex{ .position = [3]f32{ -0.5, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },
            Vertex{ .position = [3]f32{ 0.5, 0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } },
            Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } },
            Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 } },
        };

        const quad_indices = [_]u16{
            0, 1, 2,
            0, 2, 3,
        };

        engine.addIndexedRenderObject(&quad_vertices, &quad_indices, vertex_shader_path, pixel_shader_path) catch |err| {
            log(LogLevel.Error, "[ShadeFlow_AddQuadObject] Failed to add indexed render object: {}\n", .{err});
            return false;
        };

        log(LogLevel.Info, "[ShadeFlow_AddQuadObject] Quad object added successfully\n", .{});
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddQuadObject] Engine not initialized\n", .{});
    return false;
}

// 清理引擎资源
export fn ShadeFlow_Cleanup() void {
    log(LogLevel.Info, "[ShadeFlow_Cleanup] Starting global resources cleanup\n", .{});

    if (engine_instance) |engine| {
        log(LogLevel.Info, "[ShadeFlow_Cleanup] Releasing engine instance\n", .{});
        engine.deinit();
        engine_instance = null;
    }

    const leak_result = gpa.deinit();
    if (leak_result == .leak) {
        log(LogLevel.Warning, "[ShadeFlow_Cleanup] Memory leaks detected!\n", .{});
    } else {
        log(LogLevel.Info, "[ShadeFlow_Cleanup] Memory properly deallocated\n", .{});
    }

    log_callback = null;
    log(LogLevel.Info, "[ShadeFlow_Cleanup] Cleanup completed\n", .{});
}

// 获取引擎状态
export fn ShadeFlow_IsEngineInitialized() bool {
    const is_initialized = engine_instance != null;
    log(LogLevel.Debug, "[ShadeFlow_IsEngineInitialized] Engine initialized: {}\n", .{is_initialized});
    return is_initialized;
}

// 清除所有渲染对象
export fn ShadeFlow_ClearRenderObjects() bool {
    log(LogLevel.Debug, "[ShadeFlow_ClearRenderObjects] Clearing all render objects\n", .{});

    if (engine_instance) |engine| {
        engine.render_objects.deinit(allocator);
        engine.render_objects = .empty;

        engine.indexed_render_objects.deinit(allocator);
        engine.indexed_render_objects = .empty;

        log(LogLevel.Info, "[ShadeFlow_ClearRenderObjects] All render objects cleared\n", .{});
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_ClearRenderObjects] Engine not initialized\n", .{});
    return false;
}

// 注册日志回调函数
export fn ShadeFlow_RegisterLogCallback(callback: *const anyopaque) void {
    log_callback = callback;
    log(LogLevel.Info, "[ShadeFlow_RegisterLogCallback] Log callback registered successfully\n", .{});
}

// // test "Cube" {
// //     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
// //     const allocator = gpa.allocator();
// //     defer _ = gpa.deinit();
// //     var Mainwindow = try Window.init(allocator);
// //     defer Mainwindow.deinit();
// //     Mainwindow.show();

// //     const size = Mainwindow.getClientSize();

// //     var engine = try Engine.init(allocator, size.width, size.height, Mainwindow.hwnd);

// //     // 创建矩形顶点数据（由两个三角形组成）
// //     const quad_vertices = [_]Vertex{
// //         Vertex{ .position = [3]f32{ -0.5, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 左上 - 红色
// //         Vertex{ .position = [3]f32{ 0.5, 0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 右上 - 绿色
// //         Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 右下 - 蓝色
// //         Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 } }, // 左下 - 黄色
// //     };

// //     // 矩形索引数据（两个三角形）
// //     const quad_indices = [_]u16{
// //         0, 1, 2, // 第一个三角形
// //         0, 2, 3, // 第二个三角形
// //     };

// //     // 添加矩形对象
// //     try engine.addIndexedRenderObject(&quad_vertices, &quad_indices, "zig-out/shaders/TriangleVS.cso", "zig-out/shaders/TrianglePS.cso");

// //     try engine.run();
// //     defer engine.deinit();
// // }
