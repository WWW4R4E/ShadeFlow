const std = @import("std");

const win32 = @import("win32").everything;

const Buffer = @import("../d3d11/Buffer.zig").Buffer;
const Shader = @import("../d3d11/Shader.zig").Shader;
const Renderer = @import("../Renderer.zig").Renderer;

pub const CanvasRenderer = struct {
    renderer: *Renderer,
    vertex_buffer: Buffer,
    shader: Shader,

    // 顶点结构
    const Vertex = packed struct {
        position: [2]f32,
        color: [4]f32,
    };

    pub fn init(renderer: *Renderer, shader: Shader) !CanvasRenderer {
        // 创建顶点缓冲区
        const vertex_buffer = try Buffer.init(renderer.getDevice(), .vertex, 0, @sizeOf(Vertex) * 1024);

        return CanvasRenderer{
            .renderer = renderer,
            .vertex_buffer = vertex_buffer,
            .shader = shader,
        };
    }

    pub fn deinit(self: *CanvasRenderer) void {
        self.vertex_buffer.deinit();
    }

    // 绘制线条
    pub fn drawLine(self: *CanvasRenderer, x1: f32, y1: f32, x2: f32, y2: f32, color: [4]f32) !void {
        const vertices = [_]Vertex{
            .{ .position = .{ x1, y1 }, .color = color },
            .{ .position = .{ x2, y2 }, .color = color },
        };

        try self.vertex_buffer.update(self.renderer.getDeviceContext(), &vertices);

        // 使用着色器
        self.shader.use(self.renderer.getDeviceContext());

        // 绑定顶点缓冲区
        self.vertex_buffer.bindVertexBuffer(self.renderer.getDeviceContext(), 0);

        // 设置拓扑为线段列表
        self.renderer.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_LINELIST);

        // 绘制
        self.renderer.getDeviceContext().Draw(2, 0);
    }

    // 绘制矩形
    pub fn drawRect(self: *CanvasRenderer, x: f32, y: f32, width: f32, height: f32, color: [4]f32) !void {
        const vertices = [_]Vertex{
            .{ .position = .{ x, y }, .color = color },
            .{ .position = .{ x + width, y }, .color = color },
            .{ .position = .{ x + width, y + height }, .color = color },
            .{ .position = .{ x, y + height }, .color = color },
        };

        try self.vertex_buffer.update(self.renderer.getDeviceContext(), &vertices);

        // 使用着色器
        self.shader.use(self.renderer.getDeviceContext());

        // 绑定顶点缓冲区
        self.vertex_buffer.bindVertexBuffer(self.renderer.getDeviceContext(), 0);

        // 设置拓扑为线段带
        self.renderer.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_LINESTRIP);

        // 绘制
        self.renderer.getDeviceContext().Draw(4, 0);
    }

    // 填充矩形
    pub fn fillRect(self: *CanvasRenderer, x: f32, y: f32, width: f32, height: f32, color: [4]f32) !void {
        const vertices = [_]Vertex{
            // 第一个三角形
            .{ .position = .{ x, y }, .color = color },
            .{ .position = .{ x + width, y }, .color = color },
            .{ .position = .{ x + width, y + height }, .color = color },
            // 第二个三角形
            .{ .position = .{ x, y }, .color = color },
            .{ .position = .{ x + width, y + height }, .color = color },
            .{ .position = .{ x, y + height }, .color = color },
        };

        try self.vertex_buffer.update(self.renderer.getDeviceContext(), &vertices);

        // 使用着色器
        self.shader.use(self.renderer.getDeviceContext());

        // 绑定顶点缓冲区
        self.vertex_buffer.bindVertexBuffer(self.renderer.getDeviceContext(), 0);

        // 设置拓扑为三角形列表
        self.renderer.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

        // 绘制
        self.renderer.getDeviceContext().Draw(6, 0);
    }
};
