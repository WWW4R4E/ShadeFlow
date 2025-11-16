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
    const vertices = [_]Vertex{
        Vertex{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 红色顶点
        Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 绿色顶点
        Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 蓝色顶点
    };

    // 创建默认测试三角形
    try engine.addRenderObject(&vertices, "zig-out/shaders/TriangleVS.cso", "zig-out/shaders/TrianglePS.cso");

    try engine.run();
    defer engine.deinit();
}
