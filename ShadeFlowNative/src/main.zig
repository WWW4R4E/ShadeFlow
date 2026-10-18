const std = @import("std");
const Io = std.Io;

const Engine = @import("ShadeFlowNative").Engine;
const Vertex = @import("ShadeFlowNative").Vertex;
const Window = @import("ShadeFlowNative").Window;
const shader_format = @import("ShadeFlowNative").shader_format;
const GeometryGenerators = @import("ShadeFlowNative").GeometryGenerators;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var Mainwindow = try Window.init(allocator);
    defer Mainwindow.deinit();

    const size = Mainwindow.getClientSize();
    const native_handles = Mainwindow.nativeHandles() orelse return error.NoNativeWindowHandle;

    var engine = try Engine.initForHwnd(allocator, native_handles, size.width, size.height);
    engine.setWindow(Mainwindow);
    // 先销毁渲染资源，再关窗口（windowkit 的契约）。
    defer engine.destroy();

    const object_params = GeometryGenerators.GeometryParams{ .Cube = GeometryGenerators.CubeParams{ .size = 1.0 } };

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const io = threaded.io();
    const exe_path = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(exe_path);
    const app_dir = std.fs.path.dirname(exe_path).?;

    // 着色器按 exe 目录相对定位（zig-out/bin/../shaders/，与 compile_shaders.bat
    // 和 build.zig 的安装位置一致）。两边都用 fs.path.join，不再写死 `\\`。
    //
    // 后缀跟随后端而不是操作系统：Windows 默认 D3D11（fxc 的 .cso），
    // `-Dbackend=vulkan` 时和 Linux 一样读 SPIR-V（.spv）。
    const vs_name = switch (shader_format) {
        .dxbc => "Basic3DVS.cso",
        .spirv => "Basic3DVS.spv",
    };
    const ps_name = switch (shader_format) {
        .dxbc => "Basic3DPS.cso",
        .spirv => "Basic3DPS.spv",
    };

    const vs_path = try std.fs.path.join(allocator, &.{ app_dir, "..", "shaders", vs_name });
    defer allocator.free(vs_path);

    const vs_path_cstr = try allocator.allocSentinel(u8, vs_path.len, 0);
    @memcpy(vs_path_cstr, vs_path);
    defer allocator.free(vs_path_cstr);

    const ps_path = try std.fs.path.join(allocator, &.{ app_dir, "..", "shaders", ps_name });
    defer allocator.free(ps_path);

    const ps_path_cstr = try allocator.allocSentinel(u8, ps_path.len, 0);
    @memcpy(ps_path_cstr, ps_path);
    defer allocator.free(ps_path_cstr);
    // 因为addGeometryObjectWithParams导出给了C ABI，所以这里需要转换为[*:0]const u8，而不是[]u8
    engine.addGeometryObjectWithParams(&object_params, 0.1, 0.1, 0.1, vs_path_cstr.ptr, ps_path_cstr.ptr);
    engine.addGeometryObjectWithParams(&object_params, -0.5, 1, 0, vs_path_cstr.ptr, ps_path_cstr.ptr);
    try engine.run();
}
