const std = @import("std");

const win32 = @import("win32").everything;

const Buffer = @import("../renderer/d3d11/Buffer.zig").Buffer;
const Device = @import("../renderer/d3d11/Device.zig").Device;
const Shader = @import("../renderer/d3d11/Shader.zig").Shader;
const CommonInputLayouts = @import("../renderer/d3d11/Shader.zig").CommonInputLayouts;
const Renderer = @import("../renderer/Renderer.zig").Renderer;
const ShaderManager = @import("../renderer/ShaderManager.zig").ShaderManager;

pub const Vertex = struct {
    position: [3]f32,
    color: [4]f32,
};

const RenderObject = struct {
    vertex_buffer: Buffer,
    shader: Shader,
};

// 修改索引渲染对象结构体，直接包含缓冲区而不是Mesh
const IndexedRenderObject = struct {
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    shader: Shader,
    index_count: u32,
};

pub const Engine = struct {
    hwnd: win32.HWND,
    allocator: std.mem.Allocator,
    renderer: ?Renderer,
    render_objects: std.ArrayList(RenderObject),
    indexed_render_objects: std.ArrayList(IndexedRenderObject), // 新增索引渲染对象列表
    shader_manager: ShaderManager,
    size_changed: bool = false,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, hwnd: win32.HWND) !*Engine {
        var renderer: ?Renderer = null;

        std.debug.print("Window size: {}x{}\n", .{ width, height });

        // 创建渲染器
        renderer = Renderer.init(hwnd, width, height) catch |err| {
            std.debug.print("Failed to create renderer: {}\n", .{err});
            return err;
        };

        // 初始化着色器管理器
        const shader_manager = ShaderManager.init(allocator, renderer.?.getDevice());

        const engine = allocator.create(Engine) catch |err| {
            std.debug.print("Failed to allocate engine: {}\n", .{err});
            if (renderer) |*r| r.deinit();
            return err;
        };

        engine.* = Engine{
            .allocator = allocator,
            .hwnd = hwnd,
            .renderer = renderer.?,
            .render_objects = .empty,
            .indexed_render_objects = .empty, // 初始化索引渲染对象列表
            .shader_manager = shader_manager,
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
        self.indexed_render_objects.deinit(self.allocator); // 释放索引渲染对象列表
        self.shader_manager.deinit();

        if (self.renderer) |*r| {
            r.deinit();
        }
        self.allocator.destroy(self);
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

        return true;
    }

    fn render(self: *Engine) void {
        if (self.renderer) |*r| {
            r.beginFrame([4]f32{ 0.2, 0.7, 0.3, 1.0 });

            // 渲染普通对象
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
            for (self.indexed_render_objects.items) |indexed_render_object| {
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

    // 处理窗口大小变化
    fn handleResize(self: *Engine) !void {
        // 暂时不需要处理窗口大小变化
        _ = self;
        // if (self.renderer) |*r| {
        //     // 获取当前窗口客户区大小
        //     var rect: win32.RECT = undefined;
        //     if (win32.GetClientRect(self.hwnd, &rect) == 0) {
        //         return error.FailedToGetClientRect;
        //     }

        //     const width = @as(u32, @intCast(rect.right - rect.left));
        //     const height = @as(u32, @intCast(rect.bottom - rect.top));

        //     // 重新设置渲染器大小
        //     try r.resize(width, height);
        // }
    }

    // 重新加载着色器到新的设备
    fn reloadShaders(self: *Engine, device: *Device) !void {
        // 重置着色器状态，但不释放资源（因为新设备需要重新创建）
        // 这部分需要重构，但现在保持原样以兼容现有代码
        _ = self;
        _ = device;
    }
};
