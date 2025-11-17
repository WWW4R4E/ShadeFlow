const std = @import("std");

const win32 = @import("win32").everything;

const Engine = @import("engine/core/Engine.zig").Engine;
const Vertex = @import("engine/core/Engine.zig").Vertex;
const Window = @import("engine/core/Window.zig").Window;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var Mainwindow = try Window.init(allocator);
    defer Mainwindow.deinit();
    Mainwindow.show();

    const size = Mainwindow.getClientSize();

    var engine = try Engine.init(allocator, size.width, size.height, Mainwindow.hwnd);
    
    // 创建三角形顶点数据
    const triangle_vertices = [_]Vertex{
        Vertex{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 红色顶点
        Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 绿色顶点
        Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 蓝色顶点
    };

    // 创建默认测试三角形
    try engine.addRenderObject(&triangle_vertices, "zig-out/shaders/TriangleVS.cso", "zig-out/shaders/TrianglePS.cso");

    // 创建矩形顶点数据（由两个三角形组成）
    const quad_vertices = [_]Vertex{
        Vertex{ .position = [3]f32{ -0.5, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },  // 左上 - 红色
        Vertex{ .position = [3]f32{ 0.5, 0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } },   // 右上 - 绿色
        Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } },  // 右下 - 蓝色
        Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 } }, // 左下 - 黄色
    };

    // 矩形索引数据（两个三角形）
    const quad_indices = [_]u16{
        0, 1, 2, // 第一个三角形
        0, 2, 3  // 第二个三角形
    };

    // 添加矩形对象
    try engine.addIndexedRenderObject(&quad_vertices, &quad_indices, "zig-out/shaders/TriangleVS.cso", "zig-out/shaders/TrianglePS.cso");

    try engine.run();
    defer engine.deinit();
}