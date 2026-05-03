const std = @import("std");

const win32 = @import("win32").everything;

const Matrix = @import("../utils/math/Matrix.zig").Matrix;
const Quaternion = @import("../utils/math/Quaternion.zig").Quaternion;
const Time = @import("../utils/Time.zig").Time;
const Input = @import("optional/Input.zig").Input;
const Window = @import("optional/Window.zig").Window;
const Buffer = @import("render/d3d11/Buffer.zig").Buffer;
const Device = @import("render/d3d11/Device.zig").Device;
const Shader = @import("render/d3d11/Shader.zig").Shader;
const CommonInputLayouts = @import("render/d3d11/Shader.zig").CommonInputLayouts;
const Renderer = @import("render/Renderer.zig").Renderer;
const ShaderManager = @import("render/ShaderManager.zig").ShaderManager;
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
// 参考：src/engine/scene/Scene.zig（待实现）
pub const Engine = struct {
    hwnd: ?win32.HWND,
    window: ?*Window = null,
    allocator: std.mem.Allocator,
    renderer: ?Renderer,
    render_objects: std.ArrayList(RenderObject),
    indexed_render_objects: std.ArrayList(IndexedRenderObject),
    shader_manager: ShaderManager,
    size_changed: bool = false,
    time: Time,
    constant_buffer: Buffer,
    camera: Camera = Camera{},
    viewport: ?Viewport = null,

    // 为 Composition 初始化引擎
    pub fn initForComposition(allocator: std.mem.Allocator, width: u32, height: u32) !*Engine {
        var renderer = try Renderer.initForComposition(width, height);
        errdefer renderer.deinit();
        const shader_manager = ShaderManager.init(allocator, renderer.getDevice());

        const engine = allocator.create(Engine) catch |err| {
            std.debug.print("分配引擎失败: {}", .{err});
            renderer.deinit();
            return err;
        };

        // 初始化常量缓冲区
        var constant_buffer = Buffer.init(.constant);
        try constant_buffer.createConstantBuffer(renderer.getDevice(), @sizeOf(Constants));

        engine.* = Engine{
            .allocator = allocator,
            .hwnd = null,
            .renderer = renderer,
            .render_objects = .empty,
            .indexed_render_objects = .empty,
            .shader_manager = shader_manager,
            .time = Time.init(),
            .constant_buffer = constant_buffer,
            .camera = Camera{},
        };
        engine.camera.setAspectRatio(width, height);
        return engine;
    }
    // 为 HWND 初始化引擎
    pub fn initForHwnd(allocator: std.mem.Allocator, hwnd: win32.HWND, width: u32, height: u32) !*Engine {
        var renderer = try Renderer.initForHwnd(hwnd, width, height);
        errdefer renderer.deinit();

        const shader_manager = ShaderManager.init(allocator, renderer.getDevice());

        const engine = allocator.create(Engine) catch |err| {
            renderer.deinit();
            std.debug.print("分配引擎失败: {}", .{err});
            renderer.deinit();
            return err;
        };

        // 初始化常量缓冲区
        var constant_buffer = Buffer.init(.constant);
        try constant_buffer.createConstantBuffer(renderer.getDevice(), @sizeOf(Constants));

        engine.* = Engine{
            .allocator = allocator,
            .hwnd = hwnd,
            .renderer = renderer,
            .render_objects = .empty,
            .indexed_render_objects = .empty,
            .shader_manager = shader_manager,
            .time = Time.init(),
            .constant_buffer = constant_buffer,
            .camera = Camera{},
        };
        engine.camera.setAspectRatio(width, height);
        return engine;
    }

    // 添加渲染对象
    pub fn addRenderObject(self: *Engine, vertices: []const Vertex, vertex_shader_path: []const u8, pixel_shader_path: []const u8, position: [3]f32) !void {
        // 初始化顶点缓冲区
        var vertex_buffer = Buffer.init(.vertex);
        try vertex_buffer.createVertexBuffer(self.renderer.?.getDevice(), std.mem.sliceAsBytes(vertices), @sizeOf(Vertex), .immutable);

        // 将 UTF-8 字符串转换为 Windows 宽字符串（UTF-16）
        const vertex_shader_wide = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, vertex_shader_path);
        defer self.allocator.free(vertex_shader_wide);

        // 加载顶点着色器
        var vs_blob: ?*win32.ID3DBlob = null;
        var hr = win32.D3DReadFileToBlob(@ptrCast(vertex_shader_wide.ptr), &vs_blob);
        if (hr != win32.S_OK) {
            std.debug.print("加载顶点着色器 blob 失败: 0x{X}\n", .{hr});
            vertex_buffer.deinit();
            return error.FailedToLoadVertexShader;
        }
        defer _ = vs_blob.?.IUnknown.Release();

        var shader = Shader.init();
        try shader.loadVertexShader(self.renderer.?.getDevice(), @as([*]const u8, @ptrCast(vs_blob.?.GetBufferPointer()))[0..vs_blob.?.GetBufferSize()], CommonInputLayouts.positionColor());

        // 将 UTF-8 字符串转换为 Windows 宽字符串（UTF-16）
        const pixel_shader_wide = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, pixel_shader_path);
        defer self.allocator.free(pixel_shader_wide);

        // 加载像素着色器
        var ps_blob: ?*win32.ID3DBlob = null;
        hr = win32.D3DReadFileToBlob(@ptrCast(pixel_shader_wide.ptr), &ps_blob);
        if (hr != win32.S_OK) {
            std.debug.print("加载像素着色器 blob 失败: 0x{X}\n", .{hr});
            vertex_buffer.deinit();
            shader.deinit();
            return error.FailedToLoadPixelShader;
        }
        defer _ = ps_blob.?.IUnknown.Release();

        try shader.loadPixelShader(self.renderer.?.getDevice(), @as([*]const u8, @ptrCast(ps_blob.?.GetBufferPointer()))[0..ps_blob.?.GetBufferSize()]);

        // 添加到渲染对象列表
        try self.render_objects.append(self.allocator, RenderObject{
            .object = .{
                .vertex_buffer = vertex_buffer,
                .shader = shader,
                .transform = .{ .position = position },
            },
        });
    }

    // 新增：添加带索引的渲染对象
    pub fn addIndexedRenderObject(self: *Engine, vertices: []const Vertex, indices: []const u16, vertex_shader_path: []const u8, pixel_shader_path: []const u8, position: [3]f32) !void {
        // 初始化顶点缓冲区
        var vertex_buffer = Buffer.init(.vertex);
        try vertex_buffer.createVertexBuffer(self.renderer.?.getDevice(), std.mem.sliceAsBytes(vertices), @sizeOf(Vertex), .immutable);

        // 初始化索引缓冲区
        var index_buffer = Buffer.init(.index);
        try index_buffer.createIndexBuffer(self.renderer.?.getDevice(), indices);

        // 将 UTF-8 字符串转换为 Windows 宽字符串（UTF-16）
        const vertex_shader_wide = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, vertex_shader_path);
        defer self.allocator.free(vertex_shader_wide);
        // 加载顶点着色器
        var vs_blob: ?*win32.ID3DBlob = null;
        var hr = win32.D3DReadFileToBlob(@ptrCast(vertex_shader_wide.ptr), &vs_blob);
        if (hr != win32.S_OK) {
            std.debug.print("加载顶点着色器 blob 失败: 0x{X}\n", .{hr});
            vertex_buffer.deinit();
            index_buffer.deinit();
            return error.FailedToLoadVertexShader;
        }
        defer _ = vs_blob.?.IUnknown.Release();

        var shader = Shader.init();
        try shader.loadVertexShader(self.renderer.?.getDevice(), @as([*]const u8, @ptrCast(vs_blob.?.GetBufferPointer()))[0..vs_blob.?.GetBufferSize()], CommonInputLayouts.positionColor());

        // 将 UTF-8 字符串转换为 Windows 宽字符串（UTF-16）
        const pixel_shader_wide = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, pixel_shader_path);
        defer self.allocator.free(pixel_shader_wide);

        // 加载像素着色器
        var ps_blob: ?*win32.ID3DBlob = null;
        hr = win32.D3DReadFileToBlob(@ptrCast(pixel_shader_wide.ptr), &ps_blob);
        if (hr != win32.S_OK) {
            std.debug.print("加载像素着色器 blob 失败: 0x{X}\n", .{hr});
            vertex_buffer.deinit();
            index_buffer.deinit();
            shader.deinit();
            return error.FailedToLoadPixelShader;
        }
        defer _ = ps_blob.?.IUnknown.Release();

        try shader.loadPixelShader(self.renderer.?.getDevice(), @as([*]const u8, @ptrCast(ps_blob.?.GetBufferPointer()))[0..ps_blob.?.GetBufferSize()]);

        // 添加到索引渲染对象列表
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

        switch (params.*) {
            .Cube => {
                const cube_params = params.Cube;
                const geometry = GeometryGenerators.generateCube(allocator, cube_params) catch |err| {
                    std.debug.print("生成立方体错误: {}\n", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                self.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path, .{ pos_x, pos_y, pos_z }) catch |err| {
                    std.debug.print("添加立方体错误: {}\n", .{err});
                };
            },
            .Sphere => {
                const sphere_params = params.Sphere;
                const geometry = GeometryGenerators.generateSphere(allocator, sphere_params) catch |err| {
                    std.debug.print("生成球体错误: {}\n", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                self.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path, .{ pos_x, pos_y, pos_z }) catch |err| {
                    std.debug.print("添加球体错误: {}\n", .{err});
                };
            },
            .Cylinder => {
                const cylinder_params = params.Cylinder;
                const geometry = GeometryGenerators.generateCylinder(allocator, cylinder_params) catch |err| {
                    std.debug.print("生成圆柱体错误: {}\n", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                self.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path, .{ pos_x, pos_y, pos_z }) catch |err| {
                    std.debug.print("添加圆柱体错误: {}\n", .{err});
                };
            },
            .Cone => {
                const cone_params = params.Cone;
                const geometry = GeometryGenerators.generateCone(allocator, cone_params) catch |err| {
                    std.debug.print("生成圆锥体错误: {}\n", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                self.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path, .{ pos_x, pos_y, pos_z }) catch |err| {
                    std.debug.print("添加圆锥体错误: {}\n", .{err});
                };
            },
            .Line => {
                const line_params = params.Line;
                const geometry = GeometryGenerators.generateLine(allocator, line_params) catch |err| {
                    std.debug.print("生成线段错误: {}\n", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                self.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path, .{ pos_x, pos_y, pos_z }) catch |err| {
                    std.debug.print("添加线段错误: {}\n", .{err});
                };
            },
            .Rect => {
                const rect_params = params.Rect;
                const geometry = GeometryGenerators.generateRect(allocator, rect_params) catch |err| {
                    std.debug.print("生成矩形错误: {}\n", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                self.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path, .{ pos_x, pos_y, pos_z }) catch |err| {
                    std.debug.print("添加矩形错误: {}\n", .{err});
                };
            },
            .FilledRect => {
                const filled_rect_params = params.FilledRect;
                const geometry = GeometryGenerators.generateFilledRect(allocator, filled_rect_params) catch |err| {
                    std.debug.print("生成填充矩形错误: {}\n", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                self.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path, .{ pos_x, pos_y, pos_z }) catch |err| {
                    std.debug.print("添加填充矩形错误: {}\n", .{err});
                };
            },
        }
    }

    // 清除所有渲染对象
    pub fn clearRenderObjects(self: *Engine) void {
        for (self.render_objects.items) |*render_object| {
            render_object.deinit();
        }
        self.render_objects.clearAndFree(self.allocator);

        // 清除索引渲染对象
        for (self.indexed_render_objects.items) |*indexed_render_object| {
            indexed_render_object.deinit();
        }
        self.indexed_render_objects.clearAndFree(self.allocator);
    }

    pub fn deinit(self: *Engine) void {
        self.clearRenderObjects();
        self.render_objects.deinit(self.allocator);
        self.indexed_render_objects.deinit(self.allocator);
        self.shader_manager.deinit();
        self.constant_buffer.deinit();
        self.constant_buffer.deinit();

        if (self.renderer) |*r| {
            r.deinit();
        }
    }

    // 设置窗口实例
    pub fn setWindow(self: *Engine, window: *Window) void {
        self.window = window;
    }

    pub fn run(self: *Engine) !void {
        while (try self.update()) {
            self.render();
        }
    }

    pub fn update(self: *Engine) !bool {
        // 处理 Windows 消息
        var msg: win32.MSG = undefined;
        while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);

            // 如果收到 WM_QUIT 消息，则退出主循环
            if (msg.message == win32.WM_QUIT) {
                return false;
            }
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
            if (input.isMouseButtonPressed(0)) {
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
                std.debug.print("处理窗口大小变化失败: {}\n", .{err});
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
        if (self.renderer) |*r| {
            r.beginFrame([4]f32{ 0.0, 0.0, 0.0, 0.0 });

            // 获取相机的视图矩阵和投影矩阵
            const view_matrix = self.camera.getViewMatrix();
            const proj_matrix = self.camera.getProjectionMatrix();

            // 渲染普通对象
            for (self.render_objects.items) |render_object| {
                // 从物体的 transform 获取世界矩阵
                const world_matrix = render_object.object.transform.getWorldMatrix();

                // 更新常量缓冲区
                const constants = Constants{
                    .mView = view_matrix,
                    .mProj = proj_matrix,
                    .mWorld = world_matrix,
                    .gColor = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
                    .timeAndSelect = [4]f32{
                        @as(f32, @floatCast(self.time.getTotalTime())),
                        if (render_object.object.is_select) 1.0 else 0.0,
                        0.0,
                        0.0,
                    },
                };
                self.constant_buffer.updateConstantBuffer(r.getDeviceContext(), std.mem.asBytes(&constants)) catch |err| {
                    std.debug.print("更新常量缓冲区失败: {}\n", .{err});
                };

                // 绑定常量缓冲区到顶点着色器的 b0 槽位
                self.constant_buffer.bindConstantBufferVS(r.getDeviceContext(), 0);
                // 绑定常量缓冲区到像素着色器的 b0 槽位
                self.constant_buffer.bindConstantBufferPS(r.getDeviceContext(), 0);

                // 设置渲染状态
                render_object.object.shader.use(r.getDeviceContext());
                render_object.object.vertex_buffer.bindVertexBuffer(r.getDeviceContext(), 0);
                // 设置图元拓扑为三角形列表
                r.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
                // 执行绘制调用
                r.getDeviceContext().Draw(render_object.object.vertex_buffer.count, 0);
            }

            // 渲染索引对象
            for (self.indexed_render_objects.items) |indexed_render_object| {
                // 从物体的 transform 获取世界矩阵
                const world_matrix = indexed_render_object.object.transform.getWorldMatrix();

                // 更新常量缓冲区
                const constants = Constants{
                    .mView = view_matrix,
                    .mProj = proj_matrix,
                    .mWorld = world_matrix,
                    .gColor = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
                    .timeAndSelect = [4]f32{
                        @as(f32, @floatCast(self.time.getTotalTime())),
                        if (indexed_render_object.object.is_select) 1.0 else 0.0,
                        0.0,
                        0.0,
                    },
                };
                self.constant_buffer.updateConstantBuffer(r.getDeviceContext(), std.mem.asBytes(&constants)) catch |err| {
                    std.debug.print("更新常量缓冲区失败: {}\n", .{err});
                };

                // 绑定常量缓冲区到顶点着色器的 b0 槽位
                self.constant_buffer.bindConstantBufferVS(r.getDeviceContext(), 0);
                // 绑定常量缓冲区到像素着色器的 b0 槽位
                self.constant_buffer.bindConstantBufferPS(r.getDeviceContext(), 0);

                // 设置渲染状态
                indexed_render_object.object.shader.use(r.getDeviceContext());
                // 绑定缓冲区
                indexed_render_object.object.vertex_buffer.bindVertexBuffer(r.getDeviceContext(), 0);
                indexed_render_object.index_buffer.bindIndexBuffer(r.getDeviceContext());
                // 设置图元拓扑为三角形列表
                r.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
                // 执行索引绘制调用
                r.getDeviceContext().DrawIndexed(indexed_render_object.index_count, 0, 0);
            }

            // 结束帧并呈现
            r.endFrame();
        }
    }

    // 处理窗口大小变化
    fn handleResize(self: *Engine) !void {
        if (self.window) |window| {
            const size = window.getClientSize();
            try self.resizeRenderer(size.width, size.height);
            return;
        }
        std.debug.print("无法处理窗口大小变化：没有窗口或HWND\n", .{});
    }

    /// 手动调整渲染器大小（用于外部swapchain或需要精确控制大小的场景）
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

    // 重新加载着色器到新的设备
    fn reloadShaders(self: *Engine, device: *Device) !void {
        // 重置着色器状态，但不释放资源（因为新设备需要重新创建）
        // 这部分需要重构，但现在保持原样以兼容现有代码
        _ = self;
        _ = device;
    }
};
