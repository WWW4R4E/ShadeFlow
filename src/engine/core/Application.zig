const std = @import("std");

const win32 = @import("win32").everything;

const Buffer = @import("../renderer/d3d11/Buffer.zig").Buffer;
const Device = @import("../renderer/d3d11/Device.zig").Device;
const Shader = @import("../renderer/d3d11/Shader.zig").Shader;
const CommonInputLayouts = @import("../renderer/d3d11/Shader.zig").CommonInputLayouts;
const Renderer = @import("../renderer/Renderer.zig").Renderer;
const ShaderManager = @import("../renderer/ShaderManager.zig").ShaderManager;
const Window = @import("Window.zig").Window;

// // 定义顶点结构
const Vertex = struct {
    position: [3]f32,
    color: [4]f32,
};

pub const Application = struct {
    window: *Window,
    allocator: std.mem.Allocator,
    renderer: ?Renderer,
    vertex_buffer: Buffer,
    shader: Shader,
    shader_manager: ShaderManager,

    pub fn init(allocator: std.mem.Allocator) !*Application {
        var window: ?*Window = null;
        var renderer: ?Renderer = null;
        var vertex_buffer: ?Buffer = null;
        var shader: Shader = Shader.init();

        // 初始化窗口
        window = Window.init(allocator) catch |err| {
            std.debug.print("Failed to create window: {}\n", .{err});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            return err;
        };

        // 显示窗口以确保能获取正确的尺寸
        window.?.show();

        // 获取窗口客户区域大小
        const size = window.?.getClientSize();
        std.debug.print("Window size: {}x{}\n", .{ size.width, size.height });

        // 创建渲染器
        renderer = Renderer.init(window.?.hwnd, size.width, size.height) catch |err| {
            std.debug.print("Failed to create renderer: {}\n", .{err});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            return err;
        };

        // 初始化着色器管理器
        const shader_manager = ShaderManager.init(allocator, renderer.?.getDevice());

        // 创建测试三角形数据
        const vertices = [_]Vertex{
            Vertex{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 红色顶点
            Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 绿色顶点
            Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 蓝色顶点
        };

        // 初始化顶点缓冲区
        vertex_buffer = Buffer.init(.vertex);
        vertex_buffer.?.createVertexBuffer(renderer.?.getDevice(), std.mem.sliceAsBytes(&vertices), @sizeOf(Vertex), .immutable) catch |err| {
            std.debug.print("Failed to create vertex buffer: {}\n", .{err});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            if (renderer) |*r| r.deinit();
            return err;
        };

        // 加载顶点着色器
        var vs_blob: ?*win32.ID3DBlob = null;
        var hr = win32.D3DReadFileToBlob(win32.L("C:\\Users\\123\\Desktop\\dx11_zig\\zig-out\\shaders\\TriangleVS.cso"), // 文件路径（宽字符）
            &vs_blob);
        if (hr != win32.S_OK) {
            std.debug.print("Failed to load vertex shader blob: 0x{X}\n", .{hr});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            return error.FailedToLoadVertexShader;
        }
        defer _ = vs_blob.?.IUnknown.Release();

        shader.loadVertexShader(renderer.?.getDevice(), @as([*]const u8, @ptrCast(vs_blob.?.GetBufferPointer()))[0..vs_blob.?.GetBufferSize()], CommonInputLayouts.positionColor()) catch |err| {
            std.debug.print("Failed to create vertex shader: {}\n", .{err});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return err;
        };

        // 加载像素着色器
        var ps_blob: ?*win32.ID3DBlob = null;
        hr = win32.D3DReadFileToBlob(win32.L("C:\\Users\\123\\Desktop\\dx11_zig\\zig-out\\shaders\\TrianglePS.cso"), // 文件路径（宽字符）
            &ps_blob);
        if (hr != win32.S_OK) {
            std.debug.print("Failed to load pixel shader blob: 0x{X}\n", .{hr});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return error.FailedToLoadPixelShader;
        }
        defer _ = ps_blob.?.IUnknown.Release();

        shader.loadPixelShader(renderer.?.getDevice(), @as([*]const u8, @ptrCast(ps_blob.?.GetBufferPointer()))[0..ps_blob.?.GetBufferSize()]) catch |err| {
            std.debug.print("Failed to create pixel shader: {}\n", .{err});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return err;
        };
        const app = allocator.create(Application) catch |err| {
            std.debug.print("Failed to allocate application: {}\n", .{err});
            // 清理已分配的资源
            if (window) |w| w.deinit();
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return err;
        };

        app.* = Application{
            .allocator = allocator,
            .window = window.?,
            .renderer = renderer.?,
            .vertex_buffer = vertex_buffer.?,
            .shader = shader,
            .shader_manager = shader_manager,
        };

        return app;
    }

    pub fn deinit(self: *Application) void {
        self.vertex_buffer.deinit();
        self.shader.deinit();
        self.shader_manager.deinit();

        if (self.renderer) |*r| {
            r.deinit();
        }
        self.window.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *Application) !void {
        while (self.update()) {
            self.render();
        }
    }

    fn update(self: *Application) bool {
        if (!self.window.processMessages()) {
            return false;
        }

        if (self.window.size_changed) {
            // 复杂情况下，可能需要重新创建渲染器、着色器和顶点缓冲区
            // if (self.renderer) |*r| {
            //     const size = self.window.getClientSize();
            //     // 重新创建渲染器以适应新大小
            //     r.deinit();
            //     self.renderer = Renderer.init(self.window.hwnd, size.width, size.height) catch null;

            //     // 重新加载着色器到新的渲染器
            //     if (self.renderer) |*new_renderer| {
            //         self.reloadShaders(new_renderer.getDevice()) catch {
            //             std.debug.print("Failed to reload shaders after window resize\n", .{});
            //         };

            //         // 重新创建顶点缓冲区到新的设备
            //         self.recreateVertexBuffer(new_renderer.getDevice()) catch {
            //             std.debug.print("Failed to recreate vertex buffer after window resize\n", .{});
            //         };
            //     }
            // }
            self.window.size_changed = false;
        }

        return true;
    }

    fn render(self: *Application) void {
        if (self.renderer) |*r| {
            r.beginFrame([4]f32{ 0.2, 0.7, 0.3, 1.0 });
            // 设置渲染状态
            self.shader.use(r.getDeviceContext());
            self.vertex_buffer.bindVertexBuffer(r.getDeviceContext(), 0);
            // 设置图元拓扑为三角形列表
            r.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            // 执行绘制调用
            r.getDeviceContext().Draw(3, 0);

            // 结束帧并呈现
            r.endFrame();
        }
    }

    // 允许子类覆盖这些方法，实现C++类似的override模式
    pub fn onCreate(self: *Application) !void {
        _ = self; // 显式使用self参数以消除未使用参数警告
        // 默认实现为空，子类可以覆盖
    }

    pub fn onUpdate(self: *Application) void {
        _ = self; // 显式使用self参数以消除未使用参数警告
        // 默认实现为空，子类可以覆盖
    }

    pub fn onRender(self: *Application) void {
        _ = self; // 显式使用self参数以消除未使用参数警告
        // 默认实现为空，子类可以覆盖
    }

    pub fn onDestroy(self: *Application) void {
        _ = self; // 显式使用self参数以消除未使用参数警告
    }

    // 重新加载着色器到新的设备
    fn reloadShaders(self: *Application, device: *Device) !void {

        // 重置着色器状态，但不释放资源（因为新设备需要重新创建）
        self.shader.vertex_shader = null;
        self.shader.pixel_shader = null;
        self.shader.input_layout = null;

        // 重新加载顶点着色器
        var vs_blob: ?*win32.ID3DBlob = null;
        var hr = win32.D3DReadFileToBlob(win32.L("zig-out/shaders/TriangleVS.cso"), &vs_blob);
        if (hr != win32.S_OK) {
            std.debug.print("Failed to load vertex shader blob during reload: 0x{X}\n", .{hr});
            return error.FailedToLoadVertexShader;
        }
        defer _ = vs_blob.?.IUnknown.Release();

        try self.shader.loadVertexShader(device, @as([*]const u8, @ptrCast(vs_blob.?.GetBufferPointer()))[0..vs_blob.?.GetBufferSize()], CommonInputLayouts.positionColor());

        // 重新加载像素着色器
        var ps_blob: ?*win32.ID3DBlob = null;
        hr = win32.D3DReadFileToBlob(win32.L("zig-out/shaders/TrianglePS.cso"), &ps_blob);
        if (hr != win32.S_OK) {
            std.debug.print("Failed to load pixel shader blob during reload: 0x{X}\n", .{hr});
            return error.FailedToLoadPixelShader;
        }
        defer _ = ps_blob.?.IUnknown.Release();

        try self.shader.loadPixelShader(device, @as([*]const u8, @ptrCast(ps_blob.?.GetBufferPointer()))[0..ps_blob.?.GetBufferSize()]);

        std.debug.print("Shaders reloaded successfully\n", .{});
    }

    // // 重新创建顶点缓冲区到新的设备
    // fn recreateVertexBuffer(self: *Application, device: *Device) !void {
    //     std.debug.print("Recreating vertex buffer for new device...\n", .{});

    //     // 创建测试三角形数据
    //     const vertices = [_]Vertex{
    //         Vertex{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 红色顶点
    //         Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 绿色顶点
    //         Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 蓝色顶点
    //     };

    //     // 释放旧的顶点缓冲区
    //     self.vertex_buffer.deinit();

    //     // 重新创建顶点缓冲区
    //     try self.vertex_buffer.createVertexBuffer(device, std.mem.sliceAsBytes(&vertices), @sizeOf(Vertex), .immutable);

    //     std.debug.print("Vertex buffer recreated successfully\n", .{});
    // }
};
