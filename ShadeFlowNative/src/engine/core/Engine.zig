const std = @import("std");

const win32 = @import("win32").everything;

const Time = @import("../../utils/Time.zig").Time;
const Buffer = @import("../renderer/d3d11/Buffer.zig").Buffer;
const Device = @import("../renderer/d3d11/Device.zig").Device;
const Shader = @import("../renderer/d3d11/Shader.zig").Shader;
const CommonInputLayouts = @import("../renderer/d3d11/Shader.zig").CommonInputLayouts;
const Renderer = @import("../renderer/Renderer.zig").Renderer;
const ShaderManager = @import("../renderer/ShaderManager.zig").ShaderManager;

// 顶点结构，与着色器中的定义匹配
// 顶点结构，与着色器中的定义匹配
pub const Vertex = struct {
    position: [3]f32,
    // color: [4]f32,
    // color: [4]f32,
};

// 常量缓冲区结构，与着色器中的定义匹配
pub const Constants = struct {
    mView: [4][4]f32,      // 视图矩阵
    mProj: [4][4]f32,     // 投影矩阵
    mWorld: [4][4]f32,    // 世界矩阵
    gColor: [4]f32,
    time: f32,
    padding: [3]f32,
};

// 渲染对象结构
const RenderObject = struct {
    vertex_buffer: Buffer,
    shader: Shader,
};

// 索引渲染对象结构
// 索引渲染对象结构
const IndexedRenderObject = struct {
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    shader: Shader,
    index_count: u32,
};

pub const Engine = struct {
    hwnd: ?win32.HWND,
    allocator: std.mem.Allocator,
    renderer: ?Renderer,
    render_objects: std.ArrayList(RenderObject),
    indexed_render_objects: std.ArrayList(IndexedRenderObject),
    shader_manager: ShaderManager,
    size_changed: bool = false,
    time: Time,
    constant_buffer: Buffer,

    // 为 Composition 初始化引擎
    pub fn initForComposition(allocator: std.mem.Allocator, width: u32, height: u32) !*Engine {
        var renderer = try Renderer.initForComposition(width, height);
        errdefer renderer.deinit();

        const shader_manager = ShaderManager.init(allocator, renderer.getDevice());

        const engine = allocator.create(Engine) catch |err| {
            std.debug.print("Failed to allocate engine: {}", .{err});
            std.debug.print("Failed to allocate engine: {}", .{err});
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
        };
        return engine;
    }
    // 为 HWND 初始化引擎
    pub fn initForHwnd(allocator: std.mem.Allocator, hwnd: win32.HWND, width: u32, height: u32) !*Engine {
        var renderer = try Renderer.initForHwnd(hwnd, width, height);
        errdefer renderer.deinit();

        const shader_manager = ShaderManager.init(allocator, renderer.getDevice());

        const engine = allocator.create(Engine) catch |err| {
            std.debug.print("Failed to allocate engine: {}", .{err});
            renderer.deinit();
            std.debug.print("Failed to allocate engine: {}", .{err});
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
        };
        return engine;
    }

    // 添加渲染对象
    pub fn addRenderObject(self: *Engine, vertices: []const Vertex, vertex_shader_path: []const u8, pixel_shader_path: []const u8) !void {
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
            std.debug.print("Failed to load vertex shader blob: 0x{X}\n", .{hr});
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
            std.debug.print("Failed to load pixel shader blob: 0x{X}\n", .{hr});
            vertex_buffer.deinit();
            shader.deinit();
            return error.FailedToLoadPixelShader;
        }
        defer _ = ps_blob.?.IUnknown.Release();

        try shader.loadPixelShader(self.renderer.?.getDevice(), @as([*]const u8, @ptrCast(ps_blob.?.GetBufferPointer()))[0..ps_blob.?.GetBufferSize()]);

        // 添加到渲染对象列表
        try self.render_objects.append(self.allocator, RenderObject{
            .vertex_buffer = vertex_buffer,
            .shader = shader,
        });
    }

    // 新增：添加带索引的渲染对象
    pub fn addIndexedRenderObject(self: *Engine, vertices: []const Vertex, indices: []const u16, vertex_shader_path: []const u8, pixel_shader_path: []const u8) !void {
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
            std.debug.print("Failed to load vertex shader blob: 0x{X}\n", .{hr});
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
            std.debug.print("Failed to load pixel shader blob: 0x{X}\n", .{hr});
            vertex_buffer.deinit();
            index_buffer.deinit();
            shader.deinit();
            return error.FailedToLoadPixelShader;
        }
        defer _ = ps_blob.?.IUnknown.Release();

        try shader.loadPixelShader(self.renderer.?.getDevice(), @as([*]const u8, @ptrCast(ps_blob.?.GetBufferPointer()))[0..ps_blob.?.GetBufferSize()]);

        // 添加到索引渲染对象列表
        try self.indexed_render_objects.append(self.allocator, IndexedRenderObject{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .shader = shader,
            .index_count = @intCast(indices.len),
        });
    }

    // 清除所有渲染对象
    pub fn clearRenderObjects(self: *Engine) void {
        for (self.render_objects.items) |*render_object| {
            render_object.vertex_buffer.deinit();
            render_object.shader.deinit();
        }
        self.render_objects.clearAndFree(self.allocator);

        // 清除索引渲染对象
        for (self.indexed_render_objects.items) |*indexed_render_object| {
            indexed_render_object.vertex_buffer.deinit();
            indexed_render_object.index_buffer.deinit();
            indexed_render_object.shader.deinit();
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

    pub fn run(self: *Engine) !void {
        while (self.update()) {
            self.render();
        }
    }

    fn update(self: *Engine) bool {
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

        if (self.size_changed) {
            // 处理窗口大小变化
            self.handleResize() catch |err| {
                std.debug.print("Failed to handle resize: {}\n", .{err});
            };
            self.size_changed = false;
        }

        // 更新时间
        self.time.update();

        return true;
    }

    pub fn render(self: *Engine) void {
        if (self.renderer) |*r| {
            r.beginFrame([4]f32{ 0.2, 0.2, 0.3, 1.0 });

            // 创建旋转矩阵（基于时间的旋转）
            const rotation_x_time = @as(f32, @floatCast(self.time.getTotalTime())) * 0.5; // 每秒旋转半圈
            const rotation_y_time = @as(f32, @floatCast(self.time.getTotalTime())) * 0.3; // 每秒0.3圈
        
            // X轴旋转矩阵
            const rot_x_matrix = [4][4]f32{
                [4]f32{ 1.0, 0.0, 0.0, 0.0 },
                [4]f32{ 0.0, @as(f32, @cos(rotation_x_time)), @as(f32, @sin(rotation_x_time)), 0.0 },
                [4]f32{ 0.0, -@as(f32, @sin(rotation_x_time)), @as(f32, @cos(rotation_x_time)), 0.0 },
                [4]f32{ 0.0, 0.0, 0.0, 1.0 },
            };
        
            // Y轴旋转矩阵
            const rot_y_matrix = [4][4]f32{
                [4]f32{ @as(f32, @cos(rotation_y_time)), 0.0, -@as(f32, @sin(rotation_y_time)), 0.0 },
                [4]f32{ 0.0, 1.0, 0.0, 0.0 },
                [4]f32{ @as(f32, @sin(rotation_y_time)), 0.0, @as(f32, @cos(rotation_y_time)), 0.0 },
                [4]f32{ 0.0, 0.0, 0.0, 1.0 },
            };
        
            // 组合旋转矩阵
            const world_matrix = self.matrixMultiply(rot_x_matrix, rot_y_matrix);
        
            // 创建简单的视图矩阵（相机在(0,0,3)，看向原点）
            const view_matrix = [4][4]f32{
                [4]f32{ 1.0, 0.0, 0.0, 0.0 },
                [4]f32{ 0.0, 1.0, 0.0, 0.0 },
                [4]f32{ 0.0, 0.0, 1.0, 0.0 },
                [4]f32{ 0.0, 0.0, -3.0, 1.0 }, // 相机位置的负值
            };
        
            // 创建投影矩阵（透视投影）
            const aspect_ratio = @as(f32, @floatFromInt(r.width)) / @as(f32, @floatFromInt(r.height));
            const fov = 1.0; // 45度视角
            const near = 0.1;
            const far = 100.0;
        
            const y_scale = 1.0 / @tan(fov / 2.0);
            const x_scale = y_scale / aspect_ratio;
            const z_scale = -(far + near) / (far - near);
            const z_offset = (-2.0 * far * near) / (far - near);
            
            const proj_matrix = [4][4]f32{
                [4]f32{ x_scale, 0.0, 0.0, 0.0 },
                [4]f32{ 0.0, y_scale, 0.0, 0.0 },
                [4]f32{ 0.0, 0.0, z_scale, -1.0 },
                [4]f32{ 0.0, 0.0, z_offset, 0.0 },
            };

            // 更新常量缓冲区
            const constants = Constants{
                .mView = view_matrix,
                .mProj = proj_matrix,
                .mWorld = world_matrix,
                .gColor = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
                .time = @floatCast(self.time.getTotalTime()),
                .padding = [3]f32{ 0.0, 0.0, 0.0 },
            };
            self.constant_buffer.updateConstantBuffer(r.getDeviceContext(), std.mem.asBytes(&constants)) catch |err| {
                std.debug.print("Failed to update constant buffer: {}\n", .{err});
            };

            // 绑定常量缓冲区到顶点着色器的 b0 槽位
            self.constant_buffer.bindConstantBufferVS(r.getDeviceContext(), 0);
            // 绑定常量缓冲区到像素着色器的 b0 槽位
            self.constant_buffer.bindConstantBufferPS(r.getDeviceContext(), 0);

            for (self.render_objects.items) |render_object| {
                // 设置渲染状态
                render_object.shader.use(r.getDeviceContext());
                render_object.vertex_buffer.bindVertexBuffer(r.getDeviceContext(), 0);
                // 设置图元拓扑为三角形列表
                r.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
                // 执行绘制调用
                r.getDeviceContext().Draw(render_object.vertex_buffer.count, 0);
            }

            // 渲染索引对象

            for (
                self.indexed_render_objects.items,
            ) |indexed_render_object| {

                // 设置渲染状态
                indexed_render_object.shader.use(r.getDeviceContext());
                // 绑定缓冲区
                indexed_render_object.vertex_buffer.bindVertexBuffer(r.getDeviceContext(), 0);
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

    // 矩阵乘法辅助函数
    fn matrixMultiply(self: *const Engine, a: [4][4]f32, b: [4][4]f32) [4][4]f32 {
        _ = self; // 避免未使用参数警告
    
        var result: [4][4]f32 = undefined;
        for (0..4) |i| {
            for (0..4) |j| {
                result[i][j] = 0.0;
                for (0..4) |k| {
                    result[i][j] += a[i][k] * b[k][j];
                }
            }
        }
        return result;
    }

    // 处理窗口大小变化
    fn handleResize(self: *Engine) !void {
        // 如果有hwnd，使用传统方法获取窗口大小
        // 对于外部swapchain的情况，需要外部调用方通过其他方式调整渲染器大小
        _ = self;
    }

    /// 手动调整渲染器大小（用于外部swapchain或需要精确控制大小的场景）
    pub fn resizeRenderer(self: *Engine, width: u32, height: u32) !void {
        if (self.renderer) |*r| {
            try r.resize(width, height);
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
