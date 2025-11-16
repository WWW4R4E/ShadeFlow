const std = @import("std");

const win32 = @import("win32").everything;

const Engine = @import("engine/core/Engine.zig").Engine;
const Vertex = @import("engine/core/Engine.zig").Vertex;
const Window = @import("engine/core/Window.zig").Window;

// test "DefaultTriangle" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     defer _ = gpa.deinit();
//     var Mainwindow = try Window.init(allocator);
//     defer Mainwindow.deinit();
//     Mainwindow.show();

//     const size = Mainwindow.getClientSize();

//     var engine = try Engine.init(allocator, size.width, size.height, Mainwindow.hwnd);
//     const vertices = [_].Vertex{
//         Vertex{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 红色顶点
//         Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 绿色顶点
//         Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 蓝色顶点
//     };

//     // 创建默认测试三角形
//     try engine.addRenderObject(&vertices, "zig-out/shaders/TriangleVS.cso", "zig-out/shaders/TrianglePS.cso");

//     try engine.run();
//     defer engine.deinit();
// }

test "Cube" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var window = try Window.init(allocator);
    defer window.deinit();
    window.show();

    const size = window.getClientSize();

    var engine = try Engine.init(allocator, size.width, size.height, window.hwnd);
    defer engine.deinit();

    // 定义立方体的顶点数据（简化版本，仅包含必要的顶点）
    const vertices = [_]Vertex{
        // 前面
        Vertex{ .position = [3]f32{ -0.5, -0.5, -0.5 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 红色
        Vertex{ .position = [3]f32{ 0.5, -0.5, -0.5 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },
        Vertex{ .position = [3]f32{ 0.5, 0.5, -0.5 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },

        Vertex{ .position = [3]f32{ 0.5, 0.5, -0.5 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },
        Vertex{ .position = [3]f32{ -0.5, 0.5, -0.5 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },
        Vertex{ .position = [3]f32{ -0.5, -0.5, -0.5 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } },
    };

    // 添加立方体渲染对象
    try engine.addRenderObject(&vertices, "zig-out/shaders/CubeVS.cso", "zig-out/shaders/CubePS.cso");

    try engine.run();
}
