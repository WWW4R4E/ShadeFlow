const std = @import("std");

const win32 = @import("win32").everything;

const Engine = @import("engine/Engine.zig").Engine;
const Vertex = @import("engine/Engine.zig").Vertex;
const Window = @import("engine/optional/Window.zig").Window;
const Renderer = @import("engine/render/Renderer.zig").Renderer;
const GeometryGenerators = @import("engine/scene/GeometryGenerators.zig").GeometryGenerators;

var gpa = std.heap.DebugAllocator(.{}){};
var allocator = gpa.allocator();

/// 日志级别枚举(对齐c#)
pub const LogLevel = enum(c_int) {
    Debug = 0,
    Info = 1,
    Warning = 2,
    Error = 3,
};

/// 全局日志回调函数变量
var log_callback: ?*const anyopaque = null;

/// 定义日志回调函数指针类型
const LogCallbackPtr = *const fn (level: c_int, message: [*c]const u8) callconv(.c) void;

/// 引擎实例的全局存储
var engine_instance: ?*Engine = null;

/// 日志输出
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
            std.debug.print("格式化日志消息失败: {}", .{err});
            return;
        };

        buffer[message.len] = 0;

        const callback = @as(LogCallbackPtr, @ptrCast(callback_ptr));
        callback(level, &buffer[0]);
    }
}

/// 创建引擎实例(用于WinUI 3 Composition模式)
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

/// 获取交换链指针
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

/// 调整渲染器大小
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

/// 渲染
export fn ShadeFlow_RenderFrame() bool {
    if (engine_instance) |engine| {
        _ = engine.update() catch unreachable;
        engine.render();
        return true;
    }
    return false;
}

/// 清理引擎资源
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

/// 获取引擎状态
export fn ShadeFlow_IsEngineInitialized() bool {
    const is_initialized = engine_instance != null;
    log(LogLevel.Debug, "[ShadeFlow_IsEngineInitialized] Engine initialized: {}\n", .{is_initialized});
    return is_initialized;
}

/// 清除所有渲染对象
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

/// 注册日志回调函数
export fn ShadeFlow_RegisterLogCallback(callback: *const anyopaque) void {
    log_callback = callback;
    log(LogLevel.Info, "[ShadeFlow_RegisterLogCallback] Log callback registered successfully\n", .{});
}

/// 添加带参数的立方体
export fn ShadeFlow_AddCubeWithParams(
    size: f32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path_ptr: [*:0]const u8,
    pixel_shader_path_ptr: [*:0]const u8,
) bool {
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Cube = GeometryGenerators.CubeParams{ .size = size },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, vertex_shader_path_ptr, pixel_shader_path_ptr);
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddCubeWithParams] Engine not initialized", .{});
    return false;
}

/// 添加带参数的球体
export fn ShadeFlow_AddSphereWithParams(
    radius: f32,
    segments: u32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path_ptr: [*:0]const u8,
    pixel_shader_path_ptr: [*:0]const u8,
) bool {
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Sphere = GeometryGenerators.SphereParams{ .radius = radius, .segments = segments },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, vertex_shader_path_ptr, pixel_shader_path_ptr);
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddSphereWithParams] Engine not initialized", .{});
    return false;
}

/// 添加带参数的圆柱体
export fn ShadeFlow_AddCylinderWithParams(
    radius: f32,
    height: f32,
    segments: u32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path_ptr: [*:0]const u8,
    pixel_shader_path_ptr: [*:0]const u8,
) bool {
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Cylinder = GeometryGenerators.CylinderParams{ .radius = radius, .height = height, .segments = segments },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, vertex_shader_path_ptr, pixel_shader_path_ptr);
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddCylinderWithParams] Engine not initialized", .{});
    return false;
}

/// 添加带参数的圆锥体
export fn ShadeFlow_AddConeWithParams(
    radius: f32,
    height: f32,
    segments: u32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path_ptr: [*:0]const u8,
    pixel_shader_path_ptr: [*:0]const u8,
) bool {
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Cone = GeometryGenerators.ConeParams{ .radius = radius, .height = height, .segments = segments },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, vertex_shader_path_ptr, pixel_shader_path_ptr);
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddConeWithParams] Engine not initialized", .{});
    return false;
}

/// 添加几何对象（使用默认参数）
export fn ShadeFlow_AddGeometryObject(
    geometry_type: c_int,
    vertex_shader_path: [*:0]const u8,
    pixel_shader_path: [*:0]const u8,
) bool {
    if (engine_instance) |engine| {
        const geom_type = @as(GeometryGenerators.GeometryType, @enumFromInt(geometry_type));
        engine.addGeometryObject(geom_type, vertex_shader_path, pixel_shader_path);
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddGeometryObject] Engine not initialized", .{});
    return false;
}

/// 添加带参数的几何对象
/// 与C# GeometryParams内存布局对齐的C-ABI结构
const CCubeParams = extern struct { type: c_int, size: f32 };
const CSphereParams = extern struct { type: c_int, radius: f32, segments: u32 };
const CCylinderParams = extern struct { type: c_int, radius: f32, height: f32, segments: u32 };
const CConeParams = extern struct { type: c_int, radius: f32, height: f32, segments: u32 };

export fn ShadeFlow_AddGeometryObjectWithParams(
    c_params: *const anyopaque,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path: [*:0]const u8,
    pixel_shader_path: [*:0]const u8,
) bool {
    if (engine_instance) |engine| {
        const type_ptr: *const c_int = @ptrCast(@alignCast(c_params));
        const geom_type = @as(GeometryGenerators.GeometryType, @enumFromInt(type_ptr.*));

        const params = switch (geom_type) {
            .Cube, .Quad, .Triangle => blk: {
                const p: *const CCubeParams = @ptrCast(@alignCast(c_params));
                break :blk GeometryGenerators.GeometryParams{ .Cube = GeometryGenerators.CubeParams{ .size = p.size } };
            },
            .Sphere => blk: {
                const p: *const CSphereParams = @ptrCast(@alignCast(c_params));
                break :blk GeometryGenerators.GeometryParams{ .Sphere = GeometryGenerators.SphereParams{ .radius = p.radius, .segments = p.segments } };
            },
            .Cylinder => blk: {
                const p: *const CCylinderParams = @ptrCast(@alignCast(c_params));
                break :blk GeometryGenerators.GeometryParams{ .Cylinder = GeometryGenerators.CylinderParams{ .radius = p.radius, .height = p.height, .segments = p.segments } };
            },
            .Cone => blk: {
                const p: *const CConeParams = @ptrCast(@alignCast(c_params));
                break :blk GeometryGenerators.GeometryParams{ .Cone = GeometryGenerators.ConeParams{ .radius = p.radius, .height = p.height, .segments = p.segments } };
            },
            .Line => blk: {
                break :blk GeometryGenerators.GeometryParams{ .Line = GeometryGenerators.LineParams{} };
            },
            .Rect => blk: {
                break :blk GeometryGenerators.GeometryParams{ .Rect = GeometryGenerators.RectParams{} };
            },
            .FilledRect => blk: {
                break :blk GeometryGenerators.GeometryParams{ .FilledRect = GeometryGenerators.RectParams{} };
            },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, vertex_shader_path, pixel_shader_path);
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddGeometryObjectWithParams] Engine not initialized", .{});
    return false;
}

/// 相机控制相关函数
/// 获取相机位置
export fn ShadeFlow_GetCameraPosition(x: *f32, y: *f32, z: *f32) void {
    if (engine_instance) |engine| {
        const pos = engine.camera.computePosition();
        x.* = pos[0];
        y.* = pos[1];
        z.* = pos[2];
        log(LogLevel.Debug, "[ShadeFlow_GetCameraPosition] Camera position: {d:.2}, {d:.2}, {d:.2}\n", .{ x.*, y.*, z.* });
    } else {
        log(LogLevel.Error, "[ShadeFlow_GetCameraPosition] Engine not initialized\n", .{});
    }
}

/// 获取相机距离
export fn ShadeFlow_GetCameraDistance() f32 {
    if (engine_instance) |engine| {
        log(LogLevel.Debug, "[ShadeFlow_GetCameraDistance] Camera distance: {d:.2}\n", .{engine.camera.distance});
        return engine.camera.distance;
    }
    log(LogLevel.Error, "[ShadeFlow_GetCameraDistance] Engine not initialized, returning default 3.0\n", .{});
    return 3.0;
}

/// 设置相机距离
export fn ShadeFlow_SetCameraDistance(distance: f32) void {
    if (engine_instance) |engine| {
        engine.camera.distance = distance;
        engine.camera.target_distance = distance;
        log(LogLevel.Info, "[ShadeFlow_SetCameraDistance] Camera distance set to: {d:.2}\n", .{distance});
    } else {
        log(LogLevel.Error, "[ShadeFlow_SetCameraDistance] Engine not initialized\n", .{});
    }
}

/// 相机缩放
export fn ShadeFlow_CameraZoom(delta: f32) void {
    if (engine_instance) |engine| {
        engine.camera.zoom(delta);
        log(LogLevel.Debug, "[ShadeFlow_CameraZoom] Camera zoom delta: {d:.2}\n", .{delta});
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraZoom] Engine not initialized\n", .{});
    }
}

/// 相机平移
export fn ShadeFlow_CameraPan(delta_x: f32, delta_y: f32) void {
    if (engine_instance) |engine| {
        engine.camera.pan(delta_x, delta_y);
        log(LogLevel.Debug, "[ShadeFlow_CameraPan] Camera pan delta: {d:.2}, {d:.2}\n", .{ delta_x, delta_y });
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraPan] Engine not initialized\n", .{});
    }
}

/// 绕中心旋转相机
export fn ShadeFlow_CameraRotateAroundCenter(delta_x: f32, delta_y: f32) void {
    if (engine_instance) |engine| {
        engine.camera.rotateAroundCenter(delta_x, delta_y);
        log(LogLevel.Debug, "[ShadeFlow_CameraRotateAroundCenter] Camera rotate delta: {d:.2}, {d:.2}\n", .{ delta_x, delta_y });
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraRotateAroundCenter] Engine not initialized\n", .{});
    }
}

/// 相机自转
export fn ShadeFlow_CameraRotateSelf(delta_x: f32, delta_y: f32) void {
    if (engine_instance) |engine| {
        engine.camera.rotateSelf(delta_x, delta_y);
        log(LogLevel.Debug, "[ShadeFlow_CameraRotateSelf] Camera self rotate delta: {d:.2}, {d:.2}\n", .{ delta_x, delta_y });
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraRotateSelf] Engine not initialized\n", .{});
    }
}

/// 设置相机宽高比
export fn ShadeFlow_CameraSetAspectRatio(width: u32, height: u32) void {
    if (engine_instance) |engine| {
        engine.camera.setAspectRatio(width, height);
        log(LogLevel.Debug, "[ShadeFlow_CameraSetAspectRatio] Aspect ratio set to: {}x{}\n", .{ width, height });
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraSetAspectRatio] Engine not initialized\n", .{});
    }
}
