//! WinUI 3（Windows）专用的 C-ABI 导出层。
//!
//! 只有 `zig build dll` 会以本文件为根模块，因此这里可以放心 import
//! `win32`：Linux 上没有 WinUI 3 / Composition，也不构建 DLL。
//! 跨平台的引擎类型出口在 `engine/root.zig`（独立 exe 与其他 Zig 使用方）。
//!
//! 输入归属：WinUI 的 XAML 控件捕获全部用户输入，C# 侧把原始事件翻译成
//! 高层命令后调 `ShadeFlow_Camera*`（对应引擎的 `Engine.camera*` 命令入口）。
//! 独立窗口模式走的是同一批引擎命令，只是翻译发生在 `src/host/Host.zig`。

const std = @import("std");
const win32 = @import("win32").everything;

// 引擎通过命名模块导入（跨模块只能用命名导入）。相对 import 会把引擎源码
// 再嵌一份进 DLL 模块，引擎就会有两份定义。
const Engine = @import("shadeflow_engine").Engine;
const GeometryGenerators = @import("shadeflow_engine").GeometryGenerators;
const shader_format = @import("shadeflow_engine").shader_format;

var gpa = std.heap.DebugAllocator(.{}){};
var allocator = gpa.allocator();

/// 排空 WinUI 宿主线程的消息队列。
///
/// Composition 模式下引擎没有自己的窗口（窗口归 WinUI 的 `SwapChainPanel`），
/// 事件循环由 C# 的 UI 线程负责；引擎每帧被 `ShadeFlow_RenderFrame` 驱动时
/// 顺手泵一下消息，保证 Win32 消息不被饿死。
fn pumpMessages() void {
    var msg: win32.MSG = undefined;
    while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}

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

// =========================================================================
// 默认着色器路径
// =========================================================================
//
// main.zig 的独立窗口宿主会自己按 exe 目录解析 `shaders/` 下的着色器；
// WinUI 3 侧 C# 不应该关心这件事，所以着色器路径参数一律可为 null，
// 回退到这里的默认值——按**宿主 exe 目录**（GetModuleFileNameW(null)）
// 相对定位 `shaders/`，后缀跟随后端（D3D12 的 .cso / Vulkan 的 .spv）。
// DLL 需要和宿主 exe 同目录（`zig build dll` 已保证）。

var default_vs: ?[:0]u8 = null;
var default_ps: ?[:0]u8 = null;
var default_tex_vs: ?[:0]u8 = null;
var default_tex_ps: ?[:0]u8 = null;

fn ensureDefaultShaderPaths() void {
    if (default_vs != null) return;

    var wbuf: [512]u16 = undefined;
    const wlen = win32.GetModuleFileNameW(null, @ptrCast(&wbuf), wbuf.len);
    if (wlen == 0 or wlen >= wbuf.len) {
        log(LogLevel.Error, "[capi] 获取宿主 exe 路径失败，默认着色器不可用\n", .{});
        return;
    }

    const page = std.heap.page_allocator;
    const exe_path_u8 = std.unicode.utf16LeToUtf8Alloc(page, wbuf[0..wlen]) catch |err| {
        log(LogLevel.Error, "[capi] exe 路径 UTF-16 转换失败: {s}\n", .{@errorName(err)});
        return;
    };
    defer page.free(exe_path_u8);

    const app_dir = std.fs.path.dirname(exe_path_u8) orelse return;
    const ext = switch (shader_format) {
        .dxbc => "cso",
        .spirv => "spv",
    };
    const names = [_][]const u8{
        "Basic3DVS",         "Basic3DPS",
        "Basic3DTexturedVS", "Basic3DTexturedPS",
    };

    const slots = [_]*?[:0]u8{ &default_vs, &default_ps, &default_tex_vs, &default_tex_ps };
    for (names, slots) |name, slot| {
        const full = std.fs.path.join(page, &.{ app_dir, "shaders", name }) catch continue;
        defer page.free(full);

        // 补后缀 + 哨兵（着色器加载吃 [*:0] / []const u8，统一转成哨兵串）。
        const with_ext = std.fmt.allocPrint(page, "{s}.{s}", .{ full, ext }) catch continue;
        const sentineled = page.allocSentinel(u8, with_ext.len, 0) catch {
            page.free(with_ext);
            continue;
        };
        @memcpy(sentineled[0..with_ext.len], with_ext);
        page.free(with_ext);
        slot.* = sentineled;
        log(LogLevel.Info, "[capi] 默认着色器: {s}\n", .{sentineled});
    }
}

/// 可空路径参数 → 哨兵切片：null 时回退默认着色器。
fn pathOrDefault(path: ?[*:0]const u8, default: ?[:0]u8) [:0]const u8 {
    if (path) |p| return std.mem.sliceTo(p, 0);
    if (default) |d| return d;
    return "";
}

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
        engine.destroy();
        engine_instance = null;
    }

    // 使用Composition模式初始化引擎
    engine_instance = Engine.initForComposition(allocator, width, height) catch |err| {
        log(LogLevel.Error, "[ShadeFlow_CreateEngineForComposition] Failed to create engine: {}\n", .{err});
        return false;
    };

    log(LogLevel.Info, "[ShadeFlow_CreateEngineForComposition] Engine created successfully\n", .{});
    ensureDefaultShaderPaths();

    // 地面参考网格：0.5 一格、±10 范围，编辑器的空间参照（独立于场景对象，
    // 不占拾取/删除索引）。失败不阻塞引擎。
    if (engine_instance) |engine| {
        if (default_vs) |vs| {
            if (default_ps) |ps| {
                engine.addGroundGrid(vs, ps, 0.5, 20) catch |err| {
                    log(LogLevel.Warning, "[capi] 地面网格创建失败: {s}\n", .{@errorName(err)});
                };
            }
        }
    }
    return true;
}

/// 获取交换链指针
export fn ShadeFlow_GetSwapChain() ?*anyopaque {
    if (engine_instance) |engine| {
        if (engine.renderer) |*renderer| {
            const swap_chain_ptr = renderer.swapChainInteropHandle();
            if (swap_chain_ptr) |ptr| {
                log(LogLevel.Debug, "[ShadeFlow_GetSwapChain] Swap chain pointer: {*}\n", .{ptr});
            }
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
        pumpMessages();
        engine.update();
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
        engine.destroy();
        engine_instance = null;
    }

    const leak_result = gpa.deinit();
    if (leak_result == .leak) {
        log(LogLevel.Warning, "[ShadeFlow_Cleanup] Memory leaks detected!\n", .{});
    } else {
        log(LogLevel.Info, "[ShadeFlow_Cleanup] Memory properly deallocated\n", .{});
    }

    // 默认着色器路径是 page_allocator 分配的，进程级一次性资源：释放后
    // 下次 CreateEngineForComposition 会重新解析（exe 目录可能已变）。
    const defaults = [_]*?[:0]u8{ &default_vs, &default_ps, &default_tex_vs, &default_tex_ps };
    for (defaults) |slot| {
        if (slot.*) |p| std.heap.page_allocator.free(p);
        slot.* = null;
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
        engine.clearRenderObjects();

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

/// 添加带参数的立方体（着色器路径传 null 用默认着色器）
export fn ShadeFlow_AddCubeWithParams(
    size: f32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path: ?[*:0]const u8,
    pixel_shader_path: ?[*:0]const u8,
) bool {
    ensureDefaultShaderPaths();
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Cube = GeometryGenerators.CubeParams{ .size = size },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, pathOrDefault(vertex_shader_path, default_vs), pathOrDefault(pixel_shader_path, default_ps));
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddCubeWithParams] Engine not initialized", .{});
    return false;
}

/// 添加带参数的球体（着色器路径传 null 用默认着色器）
export fn ShadeFlow_AddSphereWithParams(
    radius: f32,
    segments: u32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path: ?[*:0]const u8,
    pixel_shader_path: ?[*:0]const u8,
) bool {
    ensureDefaultShaderPaths();
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Sphere = GeometryGenerators.SphereParams{ .radius = radius, .segments = segments },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, pathOrDefault(vertex_shader_path, default_vs), pathOrDefault(pixel_shader_path, default_ps));
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddSphereWithParams] Engine not initialized", .{});
    return false;
}

/// 添加带参数的圆柱体（着色器路径传 null 用默认着色器）
export fn ShadeFlow_AddCylinderWithParams(
    radius: f32,
    height: f32,
    segments: u32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path: ?[*:0]const u8,
    pixel_shader_path: ?[*:0]const u8,
) bool {
    ensureDefaultShaderPaths();
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Cylinder = GeometryGenerators.CylinderParams{ .radius = radius, .height = height, .segments = segments },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, pathOrDefault(vertex_shader_path, default_vs), pathOrDefault(pixel_shader_path, default_ps));
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddCylinderWithParams] Engine not initialized", .{});
    return false;
}

/// 添加带参数的圆锥体（着色器路径传 null 用默认着色器）
export fn ShadeFlow_AddConeWithParams(
    radius: f32,
    height: f32,
    segments: u32,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path: ?[*:0]const u8,
    pixel_shader_path: ?[*:0]const u8,
) bool {
    ensureDefaultShaderPaths();
    if (engine_instance) |engine| {
        const params = GeometryGenerators.GeometryParams{
            .Cone = GeometryGenerators.ConeParams{ .radius = radius, .height = height, .segments = segments },
        };

        engine.addGeometryObjectWithParams(&params, pos_x, pos_y, pos_z, pathOrDefault(vertex_shader_path, default_vs), pathOrDefault(pixel_shader_path, default_ps));
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
        const geom_type = @as(GeometryGenerators.GeometryType, @fromBackingInt(@intCast(geometry_type)));
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
        const geom_type = @as(GeometryGenerators.GeometryType, @fromBackingInt(@intCast(type_ptr.*)));

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
        engine.cameraZoom(delta);
        log(LogLevel.Debug, "[ShadeFlow_CameraZoom] Camera zoom delta: {d:.2}\n", .{delta});
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraZoom] Engine not initialized\n", .{});
    }
}

/// 相机平移
export fn ShadeFlow_CameraPan(delta_x: f32, delta_y: f32) void {
    if (engine_instance) |engine| {
        engine.cameraPan(delta_x, delta_y);
        log(LogLevel.Debug, "[ShadeFlow_CameraPan] Camera pan delta: {d:.2}, {d:.2}\n", .{ delta_x, delta_y });
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraPan] Engine not initialized\n", .{});
    }
}

/// 绕中心旋转相机
export fn ShadeFlow_CameraRotateAroundCenter(delta_x: f32, delta_y: f32) void {
    if (engine_instance) |engine| {
        engine.cameraOrbit(delta_x, delta_y);
        log(LogLevel.Debug, "[ShadeFlow_CameraRotateAroundCenter] Camera rotate delta: {d:.2}, {d:.2}\n", .{ delta_x, delta_y });
    } else {
        log(LogLevel.Error, "[ShadeFlow_CameraRotateAroundCenter] Engine not initialized\n", .{});
    }
}

/// 相机自转
export fn ShadeFlow_CameraRotateSelf(delta_x: f32, delta_y: f32) void {
    if (engine_instance) |engine| {
        engine.cameraSelfRotate(delta_x, delta_y);
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

/// 设置相机注视点（orbit / pan 的中心）。
export fn ShadeFlow_SetCameraTarget(x: f32, y: f32, z: f32) void {
    if (engine_instance) |engine| {
        engine.camera.target = .{ x, y, z };
        log(LogLevel.Info, "[ShadeFlow_SetCameraTarget] Camera target: {d:.2}, {d:.2}, {d:.2}\n", .{ x, y, z });
    } else {
        log(LogLevel.Error, "[ShadeFlow_SetCameraTarget] Engine not initialized\n", .{});
    }
}

/// 屏幕坐标拾取（客户区物理像素，与 SwapChainPanel 尺寸同一坐标系）。
/// 返回命中对象的索引（枚举顺序，与 RemoveRenderObject 的索引同坐标系），
/// 没命中返回 -1（同时清空所有选中状态）。
export fn ShadeFlow_PickAt(screen_x: f32, screen_y: f32) c_int {
    if (engine_instance) |engine| {
        if (engine.pickAt(screen_x, screen_y)) |index| {
            return @intCast(index);
        }
        return -1;
    }
    log(LogLevel.Error, "[ShadeFlow_PickAt] Engine not initialized\n", .{});
    return -1;
}

/// 删除单个渲染对象（索引与 PickAt 返回值同坐标系；对象删除后，后面
/// 对象的索引会前移，宿主侧列表需同步）。返回是否删除成功。
export fn ShadeFlow_RemoveRenderObject(index: c_int) bool {
    if (engine_instance) |engine| {
        if (index < 0) return false;
        const ok = engine.removeRenderObject(@intCast(index));
        if (!ok) {
            log(LogLevel.Warning, "[ShadeFlow_RemoveRenderObject] 索引越界: {d}\n", .{index});
        }
        return ok;
    }
    log(LogLevel.Error, "[ShadeFlow_RemoveRenderObject] Engine not initialized\n", .{});
    return false;
}

/// 添加贴图立方体：内部生成 UV cube（每面贴图坐标），PNG/JPEG 由引擎解码。
/// 着色器路径传 null 用默认带纹理着色器（Basic3DTextured*）。
export fn ShadeFlow_AddTexturedCube(
    size: f32,
    texture_path: [*:0]const u8,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path: ?[*:0]const u8,
    pixel_shader_path: ?[*:0]const u8,
) bool {
    ensureDefaultShaderPaths();
    if (engine_instance) |engine| {
        const uv_cube = GeometryGenerators.generateCubeUV(std.heap.page_allocator, .{ .size = size }) catch |err| {
            log(LogLevel.Error, "[ShadeFlow_AddTexturedCube] 生成 UV cube 失败: {s}\n", .{@errorName(err)});
            return false;
        };
        defer {
            std.heap.page_allocator.free(uv_cube.vertices);
            std.heap.page_allocator.free(uv_cube.indices);
        }

        engine.addTexturedIndexedRenderObject(
            uv_cube.vertices,
            uv_cube.indices,
            std.mem.sliceTo(texture_path, 0),
            pathOrDefault(vertex_shader_path, default_tex_vs),
            pathOrDefault(pixel_shader_path, default_tex_ps),
            .{ pos_x, pos_y, pos_z },
        ) catch |err| {
            log(LogLevel.Error, "[ShadeFlow_AddTexturedCube] 添加贴图 cube 失败: {s}\n", .{@errorName(err)});
            return false;
        };
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddTexturedCube] Engine not initialized", .{});
    return false;
}

/// 加载 glTF / GLB 模型（每个 primitive 一个渲染对象；有贴图的 part 自动走
/// 带纹理路径）。着色器路径传 null 用默认着色器。
export fn ShadeFlow_AddGltfObject(
    path: [*:0]const u8,
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vertex_shader_path: ?[*:0]const u8,
    pixel_shader_path: ?[*:0]const u8,
    textured_vs_path: ?[*:0]const u8,
    textured_ps_path: ?[*:0]const u8,
) bool {
    ensureDefaultShaderPaths();
    if (engine_instance) |engine| {
        engine.addGltfObject(
            std.mem.sliceTo(path, 0),
            pathOrDefault(vertex_shader_path, default_vs),
            pathOrDefault(pixel_shader_path, default_ps),
            pathOrDefault(textured_vs_path, default_tex_vs),
            pathOrDefault(textured_ps_path, default_tex_ps),
            .{ pos_x, pos_y, pos_z },
        );
        return true;
    }
    log(LogLevel.Error, "[ShadeFlow_AddGltfObject] Engine not initialized", .{});
    return false;
}
