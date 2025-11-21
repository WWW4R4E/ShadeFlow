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

    var engine = try Engine.initForHwnd(allocator, Mainwindow.hwnd, size.width, size.height);
    defer {
        engine.deinit();
        allocator.destroy(engine);
    }

    // 创建矩形顶点数据（由两个三角形组成）
    const quad_vertices = [_]Vertex{
        Vertex{ .position = [3]f32{ -0.5, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 左上 - 红色
        Vertex{ .position = [3]f32{ 0.5, 0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 右上 - 绿色
        Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 右下 - 蓝色
        Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 } }, // 左下 - 黄色
    };

    // 矩形索引数据（两个三角形）
    const quad_indices = [_]u16{
        0, 1, 2, // 第一个三角形
        0, 2, 3, // 第二个三角形
    };

    // 获取应用所在目录
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);
    const app_dir = std.fs.path.dirname(exe_path).?;

    // 构建着色器路径
    const vs_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ app_dir, "\\..\\shaders\\TriangleVS.cso" });
    defer allocator.free(vs_path);
    const ps_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ app_dir, "\\..\\shaders\\TrianglePS.cso" });
    defer allocator.free(ps_path);
    // 添加矩形对象
    try engine.addIndexedRenderObject(&quad_vertices, &quad_indices, vs_path, ps_path);

    try engine.run();
}
