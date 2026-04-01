const std = @import("std");

const win32 = @import("win32").everything;

const Buffer = @import("../d3d11/Buffer.zig").Buffer;
const Shader = @import("../d3d11/Shader.zig").Shader;
const Texture = @import("../d3d11/Texture.zig").Texture;
const Renderer = @import("../Renderer.zig").Renderer;

pub const SpriteRenderer = struct {
    renderer: *Renderer,
    vertex_buffer: Buffer,
    shader: Shader,

    // 顶点结构
    const Vertex = packed struct {
        position: [2]f32,
        uv: [2]f32,
    };

    pub fn init(renderer: *Renderer, shader: Shader) !SpriteRenderer {
        // 创建顶点缓冲区
        const vertex_buffer = try Buffer.init(renderer.getDevice(), .vertex, 0, @sizeOf(Vertex) * 6);

        return SpriteRenderer{
            .renderer = renderer,
            .vertex_buffer = vertex_buffer,
            .shader = shader,
        };
    }

    pub fn deinit(self: *SpriteRenderer) void {
        self.vertex_buffer.deinit();
    }

    // 绘制精灵
    pub fn drawSprite(self: *SpriteRenderer, texture: *Texture, x: f32, y: f32, width: f32, height: f32, rotation: f32, scale_x: f32, scale_y: f32) !void {
        // 计算变换后的顶点
        const center_x = x + width * 0.5;
        const center_y = y + height * 0.5;

        const cos_rot = std.math.cos(rotation);
        const sin_rot = std.math.sin(rotation);

        // 生成顶点数据
        const vertices = [_]Vertex{
            // 左上
            .{ .position = .{ center_x + (x - center_x) * cos_rot * scale_x - (y - center_y) * sin_rot * scale_y, center_y + (x - center_x) * sin_rot * scale_x + (y - center_y) * cos_rot * scale_y }, .uv = .{ 0.0, 0.0 } },
            // 右上
            .{ .position = .{ center_x + (x + width - center_x) * cos_rot * scale_x - (y - center_y) * sin_rot * scale_y, center_y + (x + width - center_x) * sin_rot * scale_x + (y - center_y) * cos_rot * scale_y }, .uv = .{ 1.0, 0.0 } },
            // 左下
            .{ .position = .{ center_x + (x - center_x) * cos_rot * scale_x - (y + height - center_y) * sin_rot * scale_y, center_y + (x - center_x) * sin_rot * scale_x + (y + height - center_y) * cos_rot * scale_y }, .uv = .{ 0.0, 1.0 } },
            // 右上
            .{ .position = .{ center_x + (x + width - center_x) * cos_rot * scale_x - (y - center_y) * sin_rot * scale_y, center_y + (x + width - center_x) * sin_rot * scale_x + (y - center_y) * cos_rot * scale_y }, .uv = .{ 1.0, 0.0 } },
            // 右下
            .{ .position = .{ center_x + (x + width - center_x) * cos_rot * scale_x - (y + height - center_y) * sin_rot * scale_y, center_y + (x + width - center_x) * sin_rot * scale_x + (y + height - center_y) * cos_rot * scale_y }, .uv = .{ 1.0, 1.0 } },
            // 左下
            .{ .position = .{ center_x + (x - center_x) * cos_rot * scale_x - (y + height - center_y) * sin_rot * scale_y, center_y + (x - center_x) * sin_rot * scale_x + (y + height - center_y) * cos_rot * scale_y }, .uv = .{ 0.0, 1.0 } },
        };

        try self.vertex_buffer.update(self.renderer.getDeviceContext(), &vertices);

        // 使用着色器
        self.shader.use(self.renderer.getDeviceContext());

        // 绑定纹理
        texture.bind(self.renderer.getDeviceContext(), 0);

        // 绑定顶点缓冲区
        self.vertex_buffer.bindVertexBuffer(self.renderer.getDeviceContext(), 0);

        // 设置拓扑为三角形列表
        self.renderer.getDeviceContext().IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

        // 绘制
        self.renderer.getDeviceContext().Draw(6, 0);
    }
};
