//! 独立窗口应用（Windows / Linux / macOS）。
//!
//! 宿主职责：建窗口、装事件回调、跑**过程式主循环**（循环主权在宿主，
//! windowkit 只提供 pump/waitEvent 原语）。引擎（`shadeflow_engine` 模块）
//! 不认识 windowkit —— 窗口事件由 `host/Host.zig` 翻译成引擎命令
//! （`cameraZoom` / `cameraPan` / `cameraOrbit` / `cameraSelfRotate` / `pickAt`）。

const std = @import("std");
const Io = std.Io;

const windowkit = @import("windowkit");

const Engine = @import("shadeflow_engine").Engine;
const shader_format = @import("shadeflow_engine").shader_format;
const GeometryGenerators = @import("shadeflow_engine").GeometryGenerators;

const Host = @import("host/Host.zig").Host;
const native_handles = @import("host/native_handles.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // 平台对象必须有稳定地址（Wayland registry / NSApp 回调会持有它），
    // 所以放在栈上并原地初始化——这个栈帧活得比下面的事件循环久。
    var plat: windowkit.Platform = undefined;
    try plat.initInPlace(allocator);
    defer plat.deinit();

    const win = try windowkit.PlatformWindow.init(allocator, &plat, &.{
        .title = "ShadeFlow",
        .width = 900,
        .height = 600,
        .centered = true,
        .file_drop = true,
        .max_size = .{ .width = 1600, .height = 900 },
    });
    defer win.deinit();

    const px = win.framebufferSize();
    var engine = try Engine.initForHwnd(
        allocator,
        native_handles.convertNativeHandles(win.nativeHandles()),
        px.width_px,
        px.height_px,
    );
    // 契约：先销毁渲染资源，再关窗口（windowkit 的要求）。
    defer engine.destroy();

    // 宿主上下文放在栈上：windowkit 的 user_data 存的就是它的地址。
    var host = Host.init(engine);
    // windowkit 的 setUserData 只有**一个**槽位 —— 这里写一次，之后绝不再调。
    win.setUserData(&host);
    win.setInputCallback(onInput);
    win.setCloseCallback(onClose);
    win.setResizeCallback(onResize);
    // 不注册 setRenderCallback：帧节奏由下面的过程式循环掌握。

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

    const vs_path = try resolveShaderPath(allocator, io, app_dir, vs_name);
    defer allocator.free(vs_path);

    const vs_path_cstr = try allocator.allocSentinel(u8, vs_path.len, 0);
    @memcpy(vs_path_cstr, vs_path);
    defer allocator.free(vs_path_cstr);

    const ps_path = try resolveShaderPath(allocator, io, app_dir, ps_name);
    defer allocator.free(ps_path);

    const ps_path_cstr = try allocator.allocSentinel(u8, ps_path.len, 0);
    @memcpy(ps_path_cstr, ps_path);
    defer allocator.free(ps_path_cstr);

    const object_params = GeometryGenerators.GeometryParams{ .Cube = GeometryGenerators.CubeParams{ .size = 1.0 } };
    // 因为addGeometryObjectWithParams导出给了C ABI，所以这里需要转换为[*:0]const u8，而不是[]u8
    engine.addGeometryObjectWithParams(&object_params, 0.1, 0.1, 0.1, vs_path_cstr.ptr, ps_path_cstr.ptr);
    engine.addGeometryObjectWithParams(&object_params, -0.5, 1, 0, vs_path_cstr.ptr, ps_path_cstr.ptr);

    // 过程式主循环：循环主权在这里。
    //
    // - `waitEvent(16)`：没有事件就睡 16ms（~60Hz 兜底）；有输入立即醒。
    //   Wayland 上窗口被遮挡时 compositor 不发帧事件，这里自然睡住——
    //   “被遮挡即降功耗”不需要额外机制。
    // - `pump()`：非阻塞派发就绪事件（输入/关闭/缩放回调都在这里跑）。
    // - `host.frame()`：帧边界——输入状态折成引擎命令 → update → render。
    //   渲染本身的 vsync 背压来自后端 present（FIFO / swapchain），
    //   windowkit 不再替我们排节拍。
    plat.start(); // 过程式循环必须先进入运行状态（run() 的糖会自动做）
    while (plat.isRunning()) {
        _ = plat.waitEvent(16);
        plat.pump();
        if (!plat.isRunning()) break; // pump 里 onClose 可能已 quit()
        host.frame(win);
    }
}

// =========================================================================
// windowkit 回调
// =========================================================================
//
// 回调签名由 windowkit 定死，宿主上下文从 user_data 取（只有一个槽位，
// 类型参数必须和 `main.zig` 里 `setUserData` 写入的一致）。

fn onInput(win: *windowkit.PlatformWindow, event: windowkit.input.InputEvent) bool {
    const host = win.getUserData(Host) orelse return false;
    host.onInput(win, event);
    return false;
}

fn onClose(win: *windowkit.PlatformWindow) bool {
    // 返 true 允许关闭；同时停主循环。过程式模式下 quit() 只置 running =
    // false，不会像旧的阻塞 `run()` 那样需要靠 `terminate:` 打断。
    win.getPlatform().quit();
    return true;
}

fn onResize(win: *windowkit.PlatformWindow, width: f64, height: f64) void {
    const host = win.getUserData(Host) orelse return;
    host.onResize(win, width, height);
}

/// 按 exe 目录找着色器：
/// - 开发布局：`zig-out/bin/../shaders/`；
/// - macOS bundle：`ShadeFlow.app/Contents/MacOS/../Resources/shaders/`。
fn resolveShaderPath(
    allocator: std.mem.Allocator,
    io: Io,
    app_dir: []const u8,
    name: []const u8,
) ![]u8 {
    const relative_dirs = [_][]const u8{ "shaders", "Resources/shaders" };
    var last_error: anyerror = error.ShaderNotFound;

    for (relative_dirs) |dir| {
        const path = try std.fs.path.join(allocator, &.{ app_dir, "..", dir, name });
        if (std.Io.Dir.accessAbsolute(io, path, .{})) |_| {
            return path;
        } else |err| {
            last_error = err;
        }
        allocator.free(path);
    }

    std.log.err("找不到着色器 {s}（exe 目录：{s}）", .{ name, app_dir });
    return last_error;
}
