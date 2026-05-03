const std = @import("std");
const Io = std.Io;

const win32 = @import("win32").everything;

const Engine = @import("engine/Engine.zig").Engine;
const Vertex = @import("engine/Engine.zig").Vertex;
const Window = @import("engine/optional/Window.zig").Window;
const GeometryGenerators = @import("engine/scene/GeometryGenerators.zig").GeometryGenerators;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var Mainwindow = try Window.init(allocator);
    defer Mainwindow.deinit();
    Mainwindow.show();

    const size = Mainwindow.getClientSize();

    var engine = try Engine.initForHwnd(allocator, Mainwindow.hwnd, size.width, size.height);
    engine.setWindow(Mainwindow);
    defer {
        engine.deinit();
        allocator.destroy(engine);
    }

    const object_params = GeometryGenerators.GeometryParams{ .Cube = GeometryGenerators.CubeParams{ .size = 1.0 } };

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const io = threaded.io();
    const exe_path = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(exe_path);
    const app_dir = std.fs.path.dirname(exe_path).?;

    const vs_path = try std.fmt.allocPrint(allocator, "{s}\\..\\shaders\\Basic3DVS.cso", .{app_dir});
    defer allocator.free(vs_path);
    const ps_path = try std.fmt.allocPrint(allocator, "{s}\\..\\shaders\\Basic3DPS.cso", .{app_dir});
    defer allocator.free(ps_path);
    // TODO: 优化这部分反复转化
    // 确保路径以null结尾，转换为[*:0]const u8
    const vs_path_cstr = try allocator.dupeZ(u8, vs_path);
    defer allocator.free(vs_path_cstr);

    const ps_path_cstr = try allocator.dupeZ(u8, ps_path);
    defer allocator.free(ps_path_cstr);
    // 因为addGeometryObjectWithParams导出给了C ABI，所以这里需要转换为[*:0]const u8，而不是[]u8
    engine.addGeometryObjectWithParams(&object_params, 0.1, 0.1, 0.1, vs_path_cstr.ptr, ps_path_cstr.ptr);
    engine.addGeometryObjectWithParams(&object_params, -1, 1, 0, vs_path_cstr.ptr, ps_path_cstr.ptr);
    try engine.run();
}
