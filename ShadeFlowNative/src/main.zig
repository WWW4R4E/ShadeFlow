const std = @import("std");

const win32 = @import("win32").everything;

const Engine = @import("engine/core/Engine.zig").Engine;
const Vertex = @import("engine/core/Engine.zig").Vertex;
const Window = @import("engine/optional/Window.zig").Window;

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

    // const quad_vertices = [_]Vertex{
    //     Vertex{
    //         .position = [3]f32{ -0.5, 0.5, 0.0 },
    //     },
    //     Vertex{
    //         .position = [3]f32{ 0.5, 0.5, 0.0 },
    //     },
    //     Vertex{
    //         .position = [3]f32{ 0.5, -0.5, 0.0 },
    //     },
    //     Vertex{
    //         .position = [3]f32{ -0.5, -0.5, 0.0 },
    //     },
    // };

    // const quad_indices = [_]u16{
    //     0, 1, 2,
    //     0, 2, 3,
    // };
    // 定义立方体的8个顶点 (每个面的四个角)
    const cube_vertices = [_]Vertex{
        // 前面的四个顶点
        Vertex{ .position = [3]f32{ -0.5, -0.5, 0.5 } }, // 左下前
        Vertex{ .position = [3]f32{ 0.5, -0.5, 0.5 } }, // 右下前
        Vertex{ .position = [3]f32{ 0.5, 0.5, 0.5 } }, // 右上前
        Vertex{ .position = [3]f32{ -0.5, 0.5, 0.5 } }, // 左上前

        // 后面的四个顶点
        Vertex{ .position = [3]f32{ -0.5, -0.5, -0.5 } }, // 左下后
        Vertex{ .position = [3]f32{ 0.5, -0.5, -0.5 } }, // 右下后
        Vertex{ .position = [3]f32{ 0.5, 0.5, -0.5 } }, // 右上后
        Vertex{ .position = [3]f32{ -0.5, 0.5, -0.5 } }, // 左上后
    };

    // 定义立方体的索引 (12个三角形，36个索引)
    const cube_indices = [_]u16{
        // 前面
        0, 1, 2, 0, 2, 3,
        // 顶面
        3, 2, 6, 3, 6, 7,
        // 右面
        2, 1, 5, 2, 5, 6,
        // 底面
        0, 4, 5, 0, 5, 1,
        // 左面
        0, 3, 7, 0, 7, 4,
        // 后面
        4, 7, 6, 4, 6, 5,
    };

    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);
    const app_dir = std.fs.path.dirname(exe_path).?;

    const vs_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ app_dir, "\\..\\shaders\\CubeVS.cso" });
    defer allocator.free(vs_path);
    const ps_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ app_dir, "\\..\\shaders\\CubePS.cso" });
    defer allocator.free(ps_path);

    // try engine.addIndexedRenderObject(&quad_vertices, &quad_indices, vs_path, ps_path);

    try engine.addIndexedRenderObject(&cube_vertices, &cube_indices, vs_path, ps_path);

    try engine.run();
}
