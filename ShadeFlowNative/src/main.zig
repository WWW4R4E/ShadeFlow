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

    const quad_vertices = [_]Vertex{
        Vertex{ .position = [3]f32{ -0.5, 0.5, 0.0 }, .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 } }, // 左上 - 红色
        Vertex{ .position = [3]f32{ 0.5, 0.5, 0.0 }, .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 } }, // 右上 - 绿色
        Vertex{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 } }, // 右下 - 蓝色
        Vertex{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 } }, // 左下 - 黄色
    };

    const quad_indices = [_]u16{
        0, 1, 2, 
        0, 2, 3, 
    };

    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);
    const app_dir = std.fs.path.dirname(exe_path).?;

    const vs_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ app_dir, "\\..\\shaders\\TriangleVS.cso" });
    defer allocator.free(vs_path);
    const ps_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ app_dir, "\\..\\shaders\\TrianglePS.cso" });
    defer allocator.free(ps_path);

    try engine.addIndexedRenderObject(&quad_vertices, &quad_indices, vs_path, ps_path);

    try engine.run();
}
