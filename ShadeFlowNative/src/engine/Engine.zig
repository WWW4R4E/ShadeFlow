const std = @import("std");

const Matrix = @import("math/Matrix.zig").Matrix;
const Quaternion = @import("math/Quaternion.zig").Quaternion;
const Aabb = @import("math/Aabb.zig").Aabb;
const Time = @import("Time.zig").Time;
const NativeWindow = @import("render/Renderer.zig").NativeWindow;
const RendererTypes = @import("render/Renderer.zig").Types;
const Renderer = @import("render/Renderer.zig").Renderer;
const RenderObject = @import("scene/Object.zig").RenderObject;
const Object = @import("scene/Object.zig").Object;
const IndexedRenderObject = @import("scene/Object.zig").IndexedRenderObject;
const Transform = @import("scene/Transform.zig").Transform;
const Camera = @import("view/Camera.zig").Camera;
const Viewport = @import("view/Picker.zig").Viewport;
const Picker = @import("view/Picker.zig").Picker;

const GeometryGenerators = @import("scene/GeometryGenerators.zig").GeometryGenerators;
const Gltf = @import("asset/Gltf.zig");
const Png = @import("asset/Png.zig");

pub const GeometryParams = GeometryGenerators.GeometryParams;
pub const GeometryType = GeometryGenerators.GeometryType;

// 顶点结构，与着色器中的定义匹配。定义在渲染层中立的 `render/Types.zig`
// （那里还有描述它的 `position_color` 布局），这里转出一下方便外部使用。
pub const Vertex = RendererTypes.Vertex;

// 常量缓冲区结构，与着色器中的定义匹配
pub const Constants = struct {
    mView: [4][4]f32, // 视图矩阵
    mProj: [4][4]f32, // 投影矩阵
    mWorld: [4][4]f32, // 世界矩阵
    gColor: [4]f32,
    timeAndSelect: [4]f32, // x: time, y: is_select (0.0 或 1.0), z,w: 填充
    gLightDir: [4]f32, // xyz: 世界空间方向光（指向光源），w: 环境光强度
};

// 引擎主体。
//
// 引擎**不认识任何输入设备**：它只提供 `cameraZoom` / `cameraPan` /
// `cameraOrbit` / `cameraSelfRotate` / `pickAt` 这几个命令入口，由宿主
// （独立窗口 `host/Host.zig`，或 WinUI 3 的 `capi.zig`）把平台的原始事件
// 翻译成命令后调用。两种宿主走的是同一批命令入口，只是翻译发生在不同的地方。
//
// 这条边界让引擎保持纯跨平台：Composition 模式（`capi.zig`）不需要链接
// windowkit，独立窗口模式也不需要知道 WinUI 的存在。
pub const Engine = struct {
    /// 原生窗口句柄（Composition/DLL 模式下为 null）。
    native_window: ?NativeWindow,
    allocator: std.mem.Allocator,
    renderer: ?Renderer,
    render_objects: std.ArrayList(RenderObject),
    indexed_render_objects: std.ArrayList(IndexedRenderObject),
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
        native_window: NativeWindow,
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
        native_window: ?NativeWindow,
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
        // 视口在这里就建好：拾取（Picker）依赖它，宿主不需要再靠"第一帧恰好
        // 会触发一次 resize"这种间接手段把视口顶起来。
        engine.viewport = Viewport{
            .x = 0.0,
            .y = 0.0,
            .width = @as(f32, @floatFromInt(renderer.width)),
            .height = @as(f32, @floatFromInt(renderer.height)),
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

    fn computeLocalAabbTex(vertices: []const RendererTypes.VertexTex) Aabb {
        var bounds = Aabb.EMPTY;
        for (vertices) |vertex| {
            bounds.expandPoint(vertex.position);
        }
        return bounds;
    }

    /// 用顶点位置算局部包围盒（与顶点同空间，不含 `Transform`）。
    /// 顶点数据上传后就不再保留，所以必须在创建对象时算一次。
    fn computeLocalAabb(vertices: []const Vertex) Aabb {
        var bounds = Aabb.EMPTY;
        for (vertices) |vertex| {
            bounds.expandPoint(vertex.position);
        }
        return bounds;
    }

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
        );
        errdefer vertex_buffer.deinit();

        // Shader 堆分配：Pipeline 借用它，必须保证地址在 append/扩容后不变
        // （见 Object.shader 的注释）。用 page_allocator——Object.deinit 侧
        // 拿不到引擎 allocator，两边必须同一个（曾因 GPA 分配 + page_allocator
        // 释放把相邻存活对象一起 munmap，退出时崩溃）。
        const shader = try std.heap.page_allocator.create(Renderer.Shader);
        errdefer std.heap.page_allocator.destroy(shader);
        shader.* = try renderer.createShaderFromFiles(
            vertex_shader_path,
            pixel_shader_path,
            RendererTypes.position_color,
        );
        errdefer shader.deinit();

        const pipeline = try renderer.createPipeline(shader, .{});
        errdefer { var p = pipeline; p.deinit(); }

        try self.render_objects.append(self.allocator, RenderObject{
            .object = .{
                .vertex_buffer = vertex_buffer,
                .shader = shader,
                .pipeline = pipeline,
                .transform = .{ .position = position },
                .local_aabb = computeLocalAabb(vertices),
            },
        });
    }

    /// 添加带索引的渲染对象。
    pub fn addIndexedRenderObject(
        self: *Engine,
        vertices: []const Vertex,
        indices: []const u32,
        vertex_shader_path: []const u8,
        pixel_shader_path: []const u8,
        position: [3]f32,
    ) !void {
        const renderer = if (self.renderer) |*r| r else return error.EngineNotInitialized;

        var vertex_buffer = try renderer.createVertexBuffer(
            std.mem.sliceAsBytes(vertices),
            @sizeOf(Vertex),
        );
        errdefer vertex_buffer.deinit();

        var index_buffer = try renderer.createIndexBuffer(indices);
        errdefer index_buffer.deinit();

        const sp = try self.createShaderPipeline(renderer, vertex_shader_path, pixel_shader_path, RendererTypes.position_color);

        try self.appendIndexedOwnership(
            vertex_buffer,
            index_buffer,
            sp.shader,
            sp.pipeline,
            null,
            computeLocalAabb(vertices),
            position,
        );
    }

    /// 添加带纹理的渲染对象（position_texcoord 顶点 + PNG 颜色纹理）。
    ///
    /// 着色器要带 TEXCOORD 语义的变体（Basic3DTextured*），管线随布局自动
    /// 切换到带纹理变体。
    pub fn addTexturedIndexedRenderObject(
        self: *Engine,
        vertices: []const RendererTypes.VertexTex,
        indices: []const u32,
        texture_path: []const u8,
        vertex_shader_path: []const u8,
        pixel_shader_path: []const u8,
        position: [3]f32,
    ) !void {
        const renderer = if (self.renderer) |*r| r else return error.EngineNotInitialized;

        // PNG → RGBA8 → GPU 纹理（像素解完就不再需要 CPU 侧副本）。
        var image = try Png.load(self.allocator, texture_path);
        defer image.deinit(self.allocator);
        var texture: ?Renderer.Texture = try renderer.createTexture(image.pixels, image.width, image.height);
        errdefer if (texture) |*t| t.deinit();

        var vertex_buffer = try renderer.createVertexBuffer(
            std.mem.sliceAsBytes(vertices),
            @sizeOf(RendererTypes.VertexTex),
        );
        errdefer vertex_buffer.deinit();

        var index_buffer = try renderer.createIndexBuffer(indices);
        errdefer index_buffer.deinit();

        const sp = try self.createShaderPipeline(renderer, vertex_shader_path, pixel_shader_path, RendererTypes.position_texcoord);

        try self.appendIndexedOwnership(
            vertex_buffer,
            index_buffer,
            sp.shader,
            sp.pipeline,
            texture,
            computeLocalAabbTex(vertices),
            position,
        );
        texture = null; // 所有权已转移（errdefer 不再触发）
    }

    /// 从 glTF / glb 文件加载网格：**每个 primitive 一个渲染对象**。
    ///
    /// 有 baseColorTexture 的 part 走带纹理路径（tex_vs/tex_ps 着色器 +
    /// PNG/JPEG 解码建纹理）；没有的走顶点色路径（vs/ps）。与其他 add*
    /// 一致：失败只 log 不崩。
    pub fn addGltfObject(
        self: *Engine,
        path: []const u8,
        vertex_shader_path: []const u8,
        pixel_shader_path: []const u8,
        textured_vs_path: []const u8,
        textured_ps_path: []const u8,
        position: [3]f32,
    ) void {
        if (self.renderer) |*r| {
            self.addGltfObjectInner(r, path, vertex_shader_path, pixel_shader_path, textured_vs_path, textured_ps_path, position);
        } else {
            std.log.err("引擎未初始化，无法加载 glTF: {s}", .{path});
        }
    }

    fn addGltfObjectInner(
        self: *Engine,
        renderer: *Renderer,
        path: []const u8,
        vertex_shader_path: []const u8,
        pixel_shader_path: []const u8,
        textured_vs_path: []const u8,
        textured_ps_path: []const u8,
        position: [3]f32,
    ) void {
        var scene = Gltf.load(self.allocator, path) catch |err| {
            std.log.err("加载 glTF 失败（{s}）: {s}", .{ path, @errorName(err) });
            return;
        };
        defer scene.deinit(self.allocator);

        for (scene.parts, 0..) |*part, part_index| {
            if (part.image) |image_bytes| {
                // ---- 带纹理 part ----
                self.addGltfTexturedPart(renderer, part, image_bytes, textured_vs_path, textured_ps_path, position, part_index) catch |err| {
                    std.log.err("添加 glTF 贴图对象 #{d} 失败: {s}", .{ part_index, @errorName(err) });
                };
            } else {
                // ---- 顶点色 part ----
                var vertex_buffer = renderer.createVertexBuffer(
                    std.mem.sliceAsBytes(part.vertices),
                    @sizeOf(Vertex),
                ) catch |err| {
                    std.log.err("glTF part #{d} 顶点缓冲创建失败: {s}", .{ part_index, @errorName(err) });
                    continue;
                };
                var index_buffer = renderer.createIndexBuffer(part.indices) catch |err| {
                    vertex_buffer.deinit();
                    std.log.err("glTF part #{d} 索引缓冲创建失败: {s}", .{ part_index, @errorName(err) });
                    continue;
                };
                var sp = self.createShaderPipeline(renderer, vertex_shader_path, pixel_shader_path, RendererTypes.position_color) catch |err| {
                    vertex_buffer.deinit();
                    index_buffer.deinit();
                    std.log.err("glTF part #{d} 着色器创建失败: {s}", .{ part_index, @errorName(err) });
                    continue;
                };
                self.appendIndexedOwnership(
                    vertex_buffer,
                    index_buffer,
                    sp.shader,
                    sp.pipeline,
                    null,
                    computeLocalAabb(part.vertices),
                    position,
                ) catch |err| {
                    vertex_buffer.deinit();
                    index_buffer.deinit();
                    sp.shader.deinit();
                    std.heap.page_allocator.destroy(sp.shader);
                    sp.pipeline.deinit();
                    std.log.err("添加 glTF 对象 #{d} 失败: {s}", .{ part_index, @errorName(err) });
                };
            }
        }
    }

    fn addGltfTexturedPart(
        self: *Engine,
        renderer: *Renderer,
        part: *Gltf.Part,
        image_bytes: []const u8,
        textured_vs_path: []const u8,
        textured_ps_path: []const u8,
        position: [3]f32,
        part_index: usize,
    ) !void {
        // 图片字节 → RGBA8 → GPU 纹理。
        var image = try Png.loadFromMemory(self.allocator, image_bytes);
        defer image.deinit(self.allocator);
        var texture: ?Renderer.Texture = try renderer.createTexture(image.pixels, image.width, image.height);
        errdefer if (texture) |*t| t.deinit();

        var vertex_buffer = try renderer.createVertexBuffer(
            std.mem.sliceAsBytes(part.vertices_tex),
            @sizeOf(RendererTypes.VertexTex),
        );
        var index_buffer = try renderer.createIndexBuffer(part.indices);
        var sp = try self.createShaderPipeline(renderer, textured_vs_path, textured_ps_path, RendererTypes.position_texcoord);
        errdefer {
            vertex_buffer.deinit();
            index_buffer.deinit();
            sp.shader.deinit();
            std.heap.page_allocator.destroy(sp.shader);
            sp.pipeline.deinit();
        }

        try self.appendIndexedOwnership(
            vertex_buffer,
            index_buffer,
            sp.shader,
            sp.pipeline,
            texture,
            computeLocalAabbTex(part.vertices_tex),
            position,
        );
        texture = null; // 所有权转移
        _ = part_index;
    }

    /// 加载着色器 + 建管线（顶点布局决定是否走带纹理变体）。
    ///
    /// Shader 堆分配：Pipeline 借用它，必须保证地址在 append/扩容后不变
    /// （见 Object.shader 的注释）。用 page_allocator——Object.deinit 侧
    /// 拿不到引擎 allocator，两边必须同一个（曾因 GPA 分配 + page_allocator
    /// 释放把相邻存活对象一起 munmap，退出时崩溃）。
    fn createShaderPipeline(
        self: *Engine,
        renderer: *Renderer,
        vertex_shader_path: []const u8,
        pixel_shader_path: []const u8,
        layout: RendererTypes.VertexLayout,
    ) !struct { shader: *Renderer.Shader, pipeline: Renderer.Pipeline } {
        _ = self;
        const shader = try std.heap.page_allocator.create(Renderer.Shader);
        errdefer std.heap.page_allocator.destroy(shader);
        shader.* = try renderer.createShaderFromFiles(vertex_shader_path, pixel_shader_path, layout);
        errdefer shader.deinit();

        const pipeline = try renderer.createPipeline(shader, .{});
        errdefer { var p = pipeline; p.deinit(); }

        return .{ .shader = shader, .pipeline = pipeline };
    }

    /// 把建好的资源装配成渲染对象入列表。所有资源的**所有权**（缓冲、shader、
    /// pipeline、texture）都转移给对象；失败时调用方的 errdefer 负责回收。
    fn appendIndexedOwnership(
        self: *Engine,
        vertex_buffer: Renderer.Buffer,
        index_buffer: Renderer.Buffer,
        shader: *Renderer.Shader,
        pipeline: Renderer.Pipeline,
        texture: ?Renderer.Texture,
        local_aabb: Aabb,
        position: [3]f32,
    ) !void {
        try self.indexed_render_objects.append(self.allocator, IndexedRenderObject{
            .object = .{
                .vertex_buffer = vertex_buffer,
                .shader = shader,
                .pipeline = pipeline,
                .texture = texture,
                .transform = .{ .position = position },
                .local_aabb = local_aabb,
            },
            .index_buffer = index_buffer,
            .index_count = index_buffer.count,
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

    /// 推进一帧。与输入无关：宿主在调用之前已经把自己的输入翻译成命令
    /// （`cameraZoom` / `cameraPan` / … / `pickAt`）发出去了。
    pub fn update(self: *Engine) void {
        // 更新相机位置
        self.camera.update();

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
    }

    // =========================================================================
    // 命令入口（宿主驱动）
    // =========================================================================
    //
    // 引擎只认命令，不认输入设备。`capi.zig` 的 `ShadeFlow_Camera*` 与这里
    // 的入口一一对应：WinUI 侧在 C# 里翻译输入，独立窗口侧在 `host/Host.zig`
    // 里翻译输入，两边最终调用的是同一批函数。

    /// 缩放相机（Ctrl + 滚轮）。
    pub fn cameraZoom(self: *Engine, delta: f32) void {
        self.camera.zoom(delta);
    }

    /// 平移相机（Ctrl + 中键拖动）。
    pub fn cameraPan(self: *Engine, delta_x: f32, delta_y: f32) void {
        self.camera.pan(delta_x, delta_y);
    }

    /// 相机绕场景中心公转（中键拖动）。
    pub fn cameraOrbit(self: *Engine, delta_x: f32, delta_y: f32) void {
        self.camera.rotateAroundCenter(delta_x, delta_y);
    }

    /// 相机绕自身视线轴自转（Alt + 中键拖动）。
    pub fn cameraSelfRotate(self: *Engine, delta_x: f32, delta_y: f32) void {
        self.camera.rotateSelf(delta_x, delta_y);
    }

    /// 屏幕坐标拾取（客户区物理像素，与 `Viewport` 同一坐标系）。
    /// 命中就只选中该物体，没命中清空所有选中状态。
    pub fn pickAt(self: *Engine, screen_x: f32, screen_y: f32) void {
        const viewport = self.viewport orelse return;

        var all_objects = std.ArrayList(*Object).empty;
        defer all_objects.deinit(self.allocator);

        for (self.render_objects.items) |*render_object| {
            all_objects.append(self.allocator, &render_object.object) catch |err| {
                std.log.err("收集可拾取对象失败: {s}", .{@errorName(err)});
                return;
            };
        }

        for (self.indexed_render_objects.items) |*indexed_render_object| {
            all_objects.append(self.allocator, &indexed_render_object.object) catch |err| {
                std.log.err("收集可拾取对象失败: {s}", .{@errorName(err)});
                return;
            };
        }

        const result = Picker.pick(screen_x, screen_y, &viewport, &self.camera, all_objects.items);
        const picked_object: ?*Object = if (result) |hit| hit.object else null;

        for (all_objects.items) |object| {
            object.select(picked_object != null and object == picked_object.?);
        }
    }

    pub fn render(self: *Engine) void {
        const renderer = if (self.renderer) |*r| r else return;

        renderer.beginFrame(.{ 0.0, 0.0, 0.0, 0.0 });

        const view_matrix = self.camera.getViewMatrix();
        const proj_matrix = self.camera.getProjectionMatrix();

        // 渲染普通对象：常量随 draw 传入（后端写自己的环形槽位）。
        for (self.render_objects.items) |*render_object| {
            const object = &render_object.object;
            const constants = self.buildConstants(
                object.transform.getWorldMatrix(),
                object.is_select,
                view_matrix,
                proj_matrix,
            );

            renderer.draw(
                &object.pipeline,
                &object.vertex_buffer,
                object.vertex_buffer.count,
                std.mem.asBytes(&constants),
                if (object.texture) |*t| t else null,
            );
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

            renderer.drawIndexed(
                &object.pipeline,
                &object.vertex_buffer,
                &indexed_render_object.index_buffer,
                indexed_render_object.index_count,
                std.mem.asBytes(&constants),
                if (object.texture) |*t| t else null,
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
            // 方向光：右上前方（世界空间）。坐标随 RH→LH 翻转后的世界取，
            // 视觉调出来的值；ambient 固定 0.35。
            .gLightDir = .{ 0.45, 0.75, 0.45, 0.35 },
        };
    }

    // =========================================================================
    // Resize
    // =========================================================================

    /// 手动调整渲染器大小（宿主在窗口尺寸变化时调用）。
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
