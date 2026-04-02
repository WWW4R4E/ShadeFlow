const std = @import("std");

const win32 = @import("win32").everything;

const Engine = @import("engine/core/Engine.zig").Engine;
const Vertex = @import("engine/core/Engine.zig").Vertex;
const Shapes = @import("engine/core/Shapes.zig").Shapes;
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

    const cube_params = Shapes.GeometryParams{ .Cube = Shapes.CubeParams{ .size = 1.0 } };
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);
    const app_dir = std.fs.path.dirname(exe_path).?;

    const vs_path = try std.fmt.allocPrint(allocator, "{s}\\..\\shaders\\CubeVS.cso", .{app_dir});
    defer allocator.free(vs_path);
    const ps_path = try std.fmt.allocPrint(allocator, "{s}\\..\\shaders\\CubePS.cso", .{app_dir});
    defer allocator.free(ps_path);
    // TODO: 优化这部分反复转化
    // 确保路径以null结尾，转换为[*:0]const u8
    const vs_path_cstr = try allocator.dupeZ(u8, vs_path);
    defer allocator.free(vs_path_cstr);

    const ps_path_cstr = try allocator.dupeZ(u8, ps_path);
    defer allocator.free(ps_path_cstr);
    // 因为addGeometryObjectWithParams导出给了C ABI，所以这里需要转换为[*:0]const u8，而不是[]u8
    Shapes.addGeometryObjectWithParams(engine, Shapes.GeometryType.Cube, &cube_params, vs_path_cstr.ptr, ps_path_cstr.ptr);
    try engine.run();
}
