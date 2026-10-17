const std = @import("std");

const Matrix = @import("../utils/math/Matrix.zig").Matrix;
const Quaternion = @import("../utils/math/Quaternion.zig").Quaternion;
const Time = @import("../utils/Time.zig").Time;
const Window = @import("optional/Window.zig").Window;
const platform = @import("platform/mod.zig");
const render_api = @import("render/Renderer.zig");
const Renderer = render_api.Renderer;
const RenderObject = @import("scene/Object.zig").RenderObject;
const IndexedRenderObject = @import("scene/Object.zig").IndexedRenderObject;
const Transform = @import("scene/Transform.zig").Transform;
const Camera = @import("view/Camera.zig").Camera;
const Viewport = @import("view/Picker.zig").Viewport;
const Picker = @import("view/Picker.zig").Picker;

const GeometryGenerators = @import("scene/GeometryGenerators.zig").GeometryGenerators;

pub const GeometryParams = GeometryGenerators.GeometryParams;
pub const GeometryType = GeometryGenerators.GeometryType;

// 顶点结构，与着色器中的定义匹配
pub const Vertex = struct {
    position: [3]f32,
    color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
};

// 常量缓冲区结构，与着色器中的定义匹配
pub const Constants = struct {
    mView: [4][4]f32, // 视图矩阵
    mProj: [4][4]f32, // 投影矩阵
    mWorld: [4][4]f32, // 世界矩阵
    gColor: [4]f32,
    timeAndSelect: [4]f32, // x: time, y: is_select (0.0 或 1.0), z,w: 填充
};

// TODO: 后续重构计划
// 当前 Engine 承担了对象管理职责（render_objects、indexed_render_objects 及相关方法）。
// 当功能扩展（如导入模型、场景层级、对象查询、多场景切换等）时，
// 应将对象管理相关功能抽离到独立的 Scene 模块中。
pub const Engine = struct {
    /// 原生窗口句柄（Composition/DLL 模式下为 null）。
    native_window: ?render_api.NativeWindow,
    window: ?*Window = null,
    allocator: std.mem.Allocator,
    renderer: ?Renderer,
    render_objects: std.ArrayList(RenderObject),
    indexed_render_objects: std.ArrayList(IndexedRenderObject),
    size_changed: bool = false,
    time: Time,
    camera: Camera = Camera{},
    viewport: ?Viewport = null,

    // =========================================================================
    // 初始化
    // =========================================================================

    /// 为 WinUI 3 Composition 初始化（C# 通过 C-ABI 驱动；仅 Direct 后端支持）。
    pub fn initForComposition(allocator: std.mem.Allocator, width: u32, height: u32) !*Engine {
        var renderer = try Renderer.initForComposition(width, height);
        errdefer renderer.deinit();

        return create(allocator, renderer, null);
    }

    /// 为原生窗口初始化（独立窗口 demo；句柄由 windowkit 给出）。
    pub fn initForHwnd(
        allocator: std.mem.Allocator,
        native_window: render_api.NativeWindow,
        width: u32,
        height: u32,
    ) !*Engine {
        var renderer = try Renderer.initForHwnd(native_window, width, height);
        errdefer renderer.deinit();

        return create(allocator, renderer, native_window);
    }

    fn create(
        allocator: std.mem.Allocator,
        renderer: Renderer,
        native_window: ?render_api.NativeWindow,
    ) !*Engine {
        const engine = try allocator.create(Engine);
        errdefer allocator.destroy(engine);

        engine.* = .{
            .allocator = allocator,
            .native_window = native_window,
            .renderer = renderer,
            .render_objects = .empty,
            .indexed_render_objects = .empty,
            .time = Time.init(),
            .camera = Camera{},
        };
        engine.camera.setAspectRatio(renderer.width, renderer.height);
        return engine;
    }

    pub fn deinit(self: *Engine) void {
        self.clearRenderObjects();
        self.render_objects.deinit(self.allocator);
        self.indexed_render_objects.deinit(self.allocator);

        if (self.renderer) |*r| r.deinit();
        self.renderer = null;
    }

    /// 释放引擎自身（`init*` 是用 allocator.create 分配的）。
    pub fn destroy(self: *Engine) void {
        const allocator = self.allocator;
        self.deinit();
        allocator.destroy(self);
    }

    // =========================================================================
    // 对象
    // =========================================================================

    /// 添加渲染对象（非索引绘制）。
    pub fn addRenderObject(
        self: *Engine,
        vertices: []const Vertex,
        vertex_shader_path: []const u8,
        pixel_shader_path: []const u8,
        position: [3]f32,
    ) !void {
        const renderer = if (self.renderer) |*r| r else return error.EngineNotInitialized;

        var vertex_buffer = try renderer.createVertexBuffer(
            std.mem.sliceAsBytes(vertices),
            @sizeOf(Vertex),
            .immutable,
        );
        errdefer vertex_buffer.deinit();

        var shader = try renderer.createShaderFromFiles(
            vertex_shader_path,
            pixel_shader_path,
            render_api.Types.position_color,
        );
        errdefer shader.deinit();

        try self.render_objects.append(self.allocator, RenderObject{
            .object = .{
                .vertex_buffer = vertex_buffer,
                .shader = shader,
                .transform = .{ .position = position },
            },
        });
    }

    /// 添加带索引的渲染对象。
    pub fn addIndexedRenderObject(
        self: *Engine,
        vertices: []const Vertex,
        indices: []const u16,
        vertex_shader_path: []const u8,
        pixel_shader_path: []const u8,
        position: [3]f32,
    ) !void {
        const renderer = if (self.renderer) |*r| r else return error.EngineNotInitialized;

        var vertex_buffer = try renderer.createVertexBuffer(
            std.mem.sliceAsBytes(vertices),
            @sizeOf(Vertex),
            .immutable,
        );
        errdefer vertex_buffer.deinit();

        var index_buffer = try renderer.createIndexBuffer(indices);
        errdefer index_buffer.deinit();

        var shader = try renderer.createShaderFromFiles(
            vertex_shader_path,
            pixel_shader_path,
            render_api.Types.position_color,
        );
        errdefer shader.deinit();

        try self.indexed_render_objects.append(self.allocator, IndexedRenderObject{
            .object = .{
                .vertex_buffer = vertex_buffer,
                .shader = shader,
                .transform = .{ .position = position },
            },
            .index_buffer = index_buffer,
            .index_count = @as(u32, @intCast(indices.len)),
        });
    }

    // 添加几何对象（使用默认参数）
    pub fn addGeometryObject(self: *Engine, geometry_type: GeometryType, vertex_shader_path: [*:0]const u8, pixel_shader_path: [*:0]const u8) void {
        // 使用默认参数创建几何体
        const params = switch (geometry_type) {
            .Cube => GeometryParams{ .Cube = GeometryGenerators.CubeParams{} },
            .Sphere => GeometryParams{ .Sphere = GeometryGenerators.SphereParams{} },
            .Cylinder => GeometryParams{ .Cylinder = GeometryGenerators.CylinderParams{} },
            .Cone => GeometryParams{ .Cone = GeometryGenerators.ConeParams{} },
            .Line => GeometryParams{ .Line = GeometryGenerators.LineParams{} },
            .Rect => GeometryParams{ .Rect = GeometryGenerators.RectParams{} },
            .FilledRect => GeometryParams{ .FilledRect = GeometryGenerators.RectParams{} },
            else => return,
        };

        // 调用带参数的函数，位置默认为原点
        self.addGeometryObjectWithParams(&params, 0.0, 0.0, 0.0, vertex_shader_path, pixel_shader_path);
    }

    // 添加带参数的几何对象
    pub fn addGeometryObjectWithParams(self: *Engine, params: *const GeometryParams, pos_x: f32, pos_y: f32, pos_z: f32, vertex_shader_path: [*:0]const u8, pixel_shader_path: [*:0]const u8) void {
        const allocator = std.heap.page_allocator;
        // 由于export导出给了C ABI，所以这里的路径参数是[*:0]const u8，zig内部又需要转换为[]u8
        const vertex_path = std.mem.sliceTo(vertex_shader_path, 0);
        const pixel_path = std.mem.sliceTo(pixel_shader_path, 0);

        const generated = switch (params.*) {
            .Cube => GeometryGenerators.generateCube(allocator, params.Cube),
            .Sphere => GeometryGenerators.generateSphere(allocator, params.Sphere),
            .Cylinder => GeometryGenerators.generateCylinder(allocator, params.Cylinder),
            .Cone => GeometryGenerators.generateCone(allocator, params.Cone),
            .Line => GeometryGenerators.generateLine(allocator, params.Line),
            .Rect => GeometryGenerators.generateRect(allocator, params.Rect),
            .FilledRect => GeometryGenerators.generateFilledRect(allocator, params.FilledRect),
        } catch |err| {
            std.log.err("生成几何体失败（{s}）: {s}", .{ @tagName(params.*), @errorName(err) });
            return;
        };
        defer {
            allocator.free(generated.vertices);
            allocator.free(generated.indices);
        }

        self.addIndexedRenderObject(
            generated.vertices,
            generated.indices,
            vertex_path,
            pixel_path,
            .{ pos_x, pos_y, pos_z },
        ) catch |err| {
            std.log.err("添加几何体失败: {s}", .{@errorName(err)});
        };
    }

    // 清除所有渲染对象
    pub fn clearRenderObjects(self: *Engine) void {
        for (self.render_objects.items) |*render_object| {
            render_object.deinit();
        }
        self.render_objects.clearAndFree(self.allocator);

        for (self.indexed_render_objects.items) |*indexed_render_object| {
            indexed_render_object.deinit();
        }
        self.indexed_render_objects.clearAndFree(self.allocator);
    }

    // =========================================================================
    // 主循环
    // =========================================================================

    // 设置窗口实例
    pub fn setWindow(self: *Engine, window: *Window) void {
        self.window = window;
    }

    pub fn run(self: *Engine) !void {
        // 有 windowkit 窗口：交给它的阻塞事件循环 + vsync 帧节拍。
        if (self.window) |window| {
            try window.run(self);
            return;
        }
        // 无窗口（外部驱动）的兜底轮询循环。
        while (try self.update()) {
            self.render();
        }
    }

    pub fn update(self: *Engine) !bool {
        // 有 windowkit 窗口时它自己泵消息（plat.run()），这里不能再泵否则会
        // 同帧重复派发；只有外部宿主（Composition/DLL 模式，没有 Window
        // 实例）时才由引擎自己排空消息。
        if (self.window == null) {
            if (!platform.pumpMessages()) return false;
        }

        // 处理 Win32 窗口的输入
        if (self.window) |window| {
            // 同步窗口大小变化状态
            if (window.size_changed) {
                self.size_changed = true;
                window.size_changed = false;
            }

            // 获取输入状态
            const input = window.getInput();

            // 处理 Ctrl+鼠标滚轮缩放
            if (input.isZoomInput()) {
                const wheel_delta = input.getMouseWheel();
                // 调整相机距离
                self.camera.zoom(@as(f32, @floatFromInt(wheel_delta)));
                // 重置鼠标滚轮状态
                input.resetMouseWheel();
            }

            // 处理 Ctrl+鼠标中键平移
            if (input.isPanInput()) {
                const mouse_delta = input.getMouseDelta();
                // 平移相机
                self.camera.pan(@as(f32, @floatFromInt(mouse_delta.x)), @as(f32, @floatFromInt(mouse_delta.y)));
                // 重置鼠标 delta 状态
                input.resetMouseDelta();
            }

            // 处理鼠标中键绕中心旋转（不按alt键且不按ctrl键）
            if (input.isOrbitInput()) {
                const mouse_delta = input.getMouseDelta();
                // 绕中心旋转相机（公转）
                self.camera.rotateAroundCenter(@as(f32, @floatFromInt(mouse_delta.x)), @as(f32, @floatFromInt(mouse_delta.y)));
                // 重置鼠标 delta 状态
                input.resetMouseDelta();
            }

            // 处理Alt+鼠标中键相机自转
            if (input.isSelfRotateInput()) {
                const mouse_delta = input.getMouseDelta();
                // 相机自转
                self.camera.rotateSelf(@as(f32, @floatFromInt(mouse_delta.x)), @as(f32, @floatFromInt(mouse_delta.y)));
                // 重置鼠标 delta 状态
                input.resetMouseDelta();
            }

            // 处理鼠标左键点击选取物体
            if (input.isMouseButtonDown(.left)) {
                // 检查视口是否已设置
                if (self.viewport) |viewport| {
                    // 获取鼠标位置
                    const mouse_pos = input.getMousePosition();
                    const screen_x = @as(f32, @floatFromInt(mouse_pos.x));
                    const screen_y = @as(f32, @floatFromInt(mouse_pos.y));

                    // 收集所有物体到一个数组
                    var all_objects = std.ArrayList(*@import("scene/Object.zig").Object).empty;
                    defer all_objects.deinit(self.allocator);

                    for (self.render_objects.items) |*render_object| {
                        try all_objects.append(self.allocator, &render_object.object);
                    }

                    for (self.indexed_render_objects.items) |*indexed_render_object| {
                        try all_objects.append(self.allocator, &indexed_render_object.object);
                    }

                    // 调用选取功能
                    if (Picker.pick(screen_x, screen_y, &viewport, &self.camera, all_objects.items)) |selected_object| {
                        // 先取消所有物体的选中状态
                        for (all_objects.items) |object| {
                            object.select(false);
                        }
                        // 选中当前物体
                        selected_object.select(true);
                    }
                }
            }
        }

        // 更新相机位置
        self.camera.update();

        if (self.size_changed) {
            // 处理窗口大小变化
            self.handleResize() catch |err| {
                std.log.err("处理窗口大小变化失败: {s}", .{@errorName(err)});
            };
            self.size_changed = false;
        }

        // 更新时间
        self.time.update();
        const delta_time = self.time.getDeltaTime();

        // 更新所有渲染对象的变换状态
        for (self.render_objects.items) |*render_object| {
            render_object.update(delta_time);
        }

        for (self.indexed_render_objects.items) |*indexed_render_object| {
            indexed_render_object.update(delta_time);
        }

        return true;
    }

    pub fn render(self: *Engine) void {
        const renderer = if (self.renderer) |*r| r else return;

        renderer.beginFrame(.{ 0.0, 0.0, 0.0, 0.0 });

        const view_matrix = self.camera.getViewMatrix();
        const proj_matrix = self.camera.getProjectionMatrix();

        // 渲染普通对象
        for (self.render_objects.items) |*render_object| {
            const object = &render_object.object;
            const constants = self.buildConstants(
                object.transform.getWorldMatrix(),
                object.is_select,
                view_matrix,
                proj_matrix,
            );

            renderer.setConstants(std.mem.asBytes(&constants)) catch |err| {
                std.log.err("更新常量缓冲区失败: {s}", .{@errorName(err)});
                continue;
            };
            renderer.draw(&object.shader, &object.vertex_buffer, object.vertex_buffer.count);
        }

        // 渲染索引对象
        for (self.indexed_render_objects.items) |*indexed_render_object| {
            const object = &indexed_render_object.object;
            const constants = self.buildConstants(
                object.transform.getWorldMatrix(),
                object.is_select,
                view_matrix,
                proj_matrix,
            );

            renderer.setConstants(std.mem.asBytes(&constants)) catch |err| {
                std.log.err("更新常量缓冲区失败: {s}", .{@errorName(err)});
                continue;
            };
            renderer.drawIndexed(
                &object.shader,
                &object.vertex_buffer,
                &indexed_render_object.index_buffer,
                indexed_render_object.index_count,
            );
        }

        // 结束帧并呈现
        renderer.endFrame();
    }

    fn buildConstants(
        self: *Engine,
        world_matrix: [4][4]f32,
        is_select: bool,
        view_matrix: [4][4]f32,
        proj_matrix: [4][4]f32,
    ) Constants {
        return .{
            .mView = view_matrix,
            .mProj = proj_matrix,
            .mWorld = world_matrix,
            .gColor = .{ 1.0, 1.0, 1.0, 1.0 },
            .timeAndSelect = .{
                @as(f32, @floatCast(self.time.getTotalTime())),
                if (is_select) 1.0 else 0.0,
                0.0,
                0.0,
            },
        };
    }

    // =========================================================================
    // Resize
    // =========================================================================

    // 处理窗口大小变化
    fn handleResize(self: *Engine) !void {
        if (self.window) |window| {
            const size = window.getClientSize();
            try self.resizeRenderer(size.width, size.height);
            return;
        }
        std.log.warn("无法处理窗口大小变化：没有窗口", .{});
    }

    /// 手动调整渲染器大小（用于外部 swapchain 或需要精确控制大小的场景）。
    pub fn resizeRenderer(self: *Engine, width: u32, height: u32) !void {
        if (self.renderer) |*r| {
            // 设置视口大小
            self.viewport = Viewport{
                .x = 0.0,
                .y = 0.0,
                .width = @as(f32, @floatFromInt(width)),
                .height = @as(f32, @floatFromInt(height)),
            };
            try r.resize(width, height);
            // 更新相机宽高比
            self.camera.setAspectRatio(width, height);
        }
    }
};
