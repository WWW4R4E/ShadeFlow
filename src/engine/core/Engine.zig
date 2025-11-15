const std = @import("std");

const win32 = @import("win32").everything;

const Buffer = @import("../renderer/d3d11/Buffer.zig").Buffer;
const Device = @import("../renderer/d3d11/Device.zig").Device;
const Shader = @import("../renderer/d3d11/Shader.zig").Shader;
const CommonInputLayouts = @import("../renderer/d3d11/Shader.zig").CommonInputLayouts;
const Renderer = @import("../renderer/Renderer.zig").Renderer;
const ShaderManager = @import("../renderer/ShaderManager.zig").ShaderManager;

// // 定义顶点结构
const Vertex = struct {
    position: [3]f32,
    color: [4]f32,
};

pub const Engine = struct {
    hwnd: win32.HWND,
    allocator: std.mem.Allocator,
    renderer: ?Renderer,
    vertex_buffer: Buffer,
    shader: Shader,
    shader_manager: ShaderManager,
    size_changed: bool = false,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, hwnd: win32.HWND) !*Engine {
        var renderer: ?Renderer = null;
        var vertex_buffer: ?Buffer = null;
        var shader: Shader = Shader.init();

        std.debug.print("Window size: {}x{}\n", .{ width, height });

        // 创建渲染器
        renderer = Renderer.init(hwnd, width, height) catch |err| {
            std.debug.print("Failed to create renderer: {}\n", .{err});
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
            if (renderer) |*r| r.deinit();
            return err;
        };

        // 加载顶点着色器
        var vs_blob: ?*win32.ID3DBlob = null;
        var hr = win32.D3DReadFileToBlob(win32.L("C:\\Users\\123\\Desktop\\dx11_zig\\zig-out\\shaders\\TriangleVS.cso"), &vs_blob);
        if (hr != win32.S_OK) {
            std.debug.print("Failed to load vertex shader blob: 0x{X}\n", .{hr});
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            return error.FailedToLoadVertexShader;
        }
        defer _ = vs_blob.?.IUnknown.Release();

        shader.loadVertexShader(renderer.?.getDevice(), @as([*]const u8, @ptrCast(vs_blob.?.GetBufferPointer()))[0..vs_blob.?.GetBufferSize()], CommonInputLayouts.positionColor()) catch |err| {
            std.debug.print("Failed to create vertex shader: {}\n", .{err});
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return err;
        };

        // 加载像素着色器
        var ps_blob: ?*win32.ID3DBlob = null;
        hr = win32.D3DReadFileToBlob(win32.L("C:\\Users\\123\\Desktop\\dx11_zig\\zig-out\\shaders\\TrianglePS.cso"), &ps_blob);
        if (hr != win32.S_OK) {
            std.debug.print("Failed to load pixel shader blob: 0x{X}\n", .{hr});
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return error.FailedToLoadPixelShader;
        }
        defer _ = ps_blob.?.IUnknown.Release();

        shader.loadPixelShader(renderer.?.getDevice(), @as([*]const u8, @ptrCast(ps_blob.?.GetBufferPointer()))[0..ps_blob.?.GetBufferSize()]) catch |err| {
            std.debug.print("Failed to create pixel shader: {}\n", .{err});
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return err;
        };
        const app = allocator.create(Engine) catch |err| {
            std.debug.print("Failed to allocate application: {}\n", .{err});
            if (renderer) |*r| r.deinit();
            if (vertex_buffer) |*vb| vb.deinit();
            shader.deinit();
            return err;
        };

        app.* = Engine{
            .allocator = allocator,
            .hwnd = hwnd,
            .renderer = renderer.?,
            .vertex_buffer = vertex_buffer.?,
            .shader = shader,
            .shader_manager = shader_manager,
        };

        return app;
    }

    pub fn deinit(self: *Engine) void {
        self.vertex_buffer.deinit();
        self.shader.deinit();
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
};
