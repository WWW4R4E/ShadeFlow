//! ShadeFlowNative 构建脚本。
//!
//! 平台分支（与 windowkit 的构建方式一致：编译期按 target 组装模块）：
//! - Windows：`win32` + `windowkit`，产出 exe，`dll` 步骤额外产出给 WinUI 的 DLL；
//! - Linux：  只有 `windowkit`，渲染后端编译期选 Vulkan。
//!
//! 后端实现本身也是独立模块：`render_backend` 指向 d3d11 或 vulkan，只有
//! 被选中的那个会进模块图。D3D11 构建不会解析 vulkan-zig，也不会生成 `vk.zig`。
//!
//! 步骤：
//! - `zig build`             当前目标的 exe
//! - `zig build run`         运行当前目标的 exe
//! - `zig build dll`         （仅 Windows / D3D11）构建并复制 `ShadeFlowNative.dll`
//! - `zig build shaders`     着色器 → SPIR-V（Vulkan 后端），已挂进 install 步骤
//!
//! Windows 默认仍是 D3D11；用 `zig build run -Dbackend=vulkan` 切到 Vulkan 后端。
//! Vulkan 着色器需要 `glslc`（Vulkan SDK / shaderc）：
//! 按 `-Dglslc=<path>` → PATH → `%VULKAN_SDK%` 的顺序查找。

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const is_windows = target.result.os.tag == .windows;
    if (!is_windows and target.result.os.tag != .linux) {
        @panic("只支持 Windows（D3D11/Vulkan）与 Linux（Vulkan）目标");
    }

    // Windows 可以二选一：默认 d3d11，`-Dbackend=vulkan` 切到 Vulkan。
    // Linux 固定 Vulkan（与 backend/mod.zig 的分支保持一致）。
    const windows_backend = b.option(
        []const u8,
        "backend",
        "Windows 渲染后端：d3d11（默认）或 vulkan",
    ) orelse "d3d11";
    if (!std.mem.eql(u8, windows_backend, "d3d11") and !std.mem.eql(u8, windows_backend, "vulkan")) {
        @panic("backend 只能是 d3d11 或 vulkan");
    }
    const use_vulkan = !is_windows or std.mem.eql(u8, windows_backend, "vulkan");

    const windowkit = b.dependency("windowkit", .{
        .target = target,
        .optimize = optimize,
    }).module("windowkit");
    const win32 = b.dependency("win32", .{}).module("win32");

    // 只有确实要用 Vulkan 时才解析 vulkan-zig：它会用 vendor/vk.xml 生成
    // 绑定，D3D11 默认构建不该为它付出配置/生成成本。
    const vulkan: ?*std.Build.Module = if (use_vulkan) b.dependency("vulkan", .{
        .registry = b.path("vendor/vk.xml"),
        .optimize = optimize,
    }).module("vulkan-zig") else null;

    // 后端中立的描述类型单独成模块：后端实现与引擎共享同一份类型，
    // 否则 `NativeWindow` 等跨边界类型会变成两个不同的类型。
    const render_types = b.createModule(.{
        .root_source_file = b.path("src/engine/render/Types.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 每个后端是一个独立模块，依赖只在它自己身上：
    // - d3d11 跟着 win32 走，Windows 上始终可用；
    // - vulkan 只在 `-Dbackend=vulkan`（或 Linux）时才创建。
    const d3d11_backend: ?*std.Build.Module = if (is_windows) b.createModule(.{
        .root_source_file = b.path("src/engine/render/backend/d3d11/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = win32 },
            .{ .name = "render_types", .module = render_types },
        },
    }) else null;

    const vulkan_backend: ?*std.Build.Module = if (vulkan) |vulkan_mod| blk: {
        var imports: [3]std.Build.Module.Import = undefined;
        var count: usize = 0;
        imports[count] = .{ .name = "vulkan", .module = vulkan_mod };
        count += 1;
        imports[count] = .{ .name = "render_types", .module = render_types };
        count += 1;
        // Windows 上 loader 走 kernel32 的 LoadLibraryA/GetProcAddress。
        if (is_windows) {
            imports[count] = .{ .name = "win32", .module = win32 };
            count += 1;
        }
        break :blk b.createModule(.{
            .root_source_file = b.path("src/engine/render/backend/vulkan/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = imports[0..count],
        });
    } else null;

    // 引擎只看到这个 `render_backend`：它指向哪个后端，就只编译哪个后端。
    const render_backend = if (use_vulkan) vulkan_backend.? else d3d11_backend.?;

    // 跨平台引擎模块（exe 用）。Linux 分支不引入 win32。
    const engine_mod = createEngineModule(
        b,
        target,
        optimize,
        windowkit,
        render_types,
        render_backend,
    );

    // 构建 EXE（默认）
    const exe = b.addExecutable(.{
        .name = "ShadeFlowNative",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ShadeFlowNative", .module = engine_mod },
            },
        }),
    });
    b.installArtifact(exe);

    // run 步骤
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.option([]const u8, "args", "Arguments for the run step")) |args| {
        var it = std.mem.splitScalar(u8, args, ' ');
        while (it.next()) |a| {
            if (a.len != 0) run_cmd.addArg(a);
        }
    }
    run_step.dependOn(&run_cmd.step);

    // dll 步骤：C-ABI 导出在 capi.zig，只有 Windows 有 WinUI 宿主。
    const dll_step = b.step("dll", "Build DLL and copy to ShadeFlowUI (Windows only)");
    if (is_windows and use_vulkan) {
        dll_step.dependOn(&b.addFail(
            "WinUI Composition 模式只支持 D3D11；Vulkan 后端请用 zig build run -Dbackend=vulkan",
        ).step);
    } else if (is_windows) {
        const dll_copy_path = "../../ShadeFlowUI/";
        const capi_mod = b.createModule(.{
            .root_source_file = b.path("src/capi.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "win32", .module = win32 },
                .{ .name = "windowkit", .module = windowkit },
                .{ .name = "render_types", .module = render_types },
                .{ .name = "render_backend", .module = render_backend },
            },
        });
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "ShadeFlowNative",
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .root_module = capi_mod,
        });
        b.installArtifact(lib);

        const install_dll = b.addInstallFile(lib.getEmittedBin(), b.fmt("{s}/ShadeFlowNative.dll", .{dll_copy_path}));
        dll_step.dependOn(&install_dll.step);
    } else {
        dll_step.dependOn(&b.addFail("ShadeFlowNative.dll 只用于 Windows 上的 WinUI 3 宿主").step);
    }

    // SPIR-V：Vulkan 后端的着色器。产物统一叫 Basic3DVS/Basic3DPS.spv，
    // 装到 zig-out/shaders/（main.zig 按 exe 目录相对定位）。
    //
    // Windows 也用 GLSL 那两份源码（Basic3D.vert/.frag）：Windows SDK 自带的
    // dxc.exe 没开 SPIR-V codegen，所以统一用 glslc。
    const shaders_step = b.step("shaders", "Compile shaders to SPIR-V (Vulkan backend)");
    if (use_vulkan) {
        const glslc = resolveGlslc(b);
        const glsl_sources = [_]struct { src: []const u8, out: []const u8 }{
            .{ .src = "assets/shaders/Basic3D.vert", .out = "Basic3DVS.spv" },
            .{ .src = "assets/shaders/Basic3D.frag", .out = "Basic3DPS.spv" },
        };

        for (glsl_sources) |shader| {
            const compile = b.addSystemCommand(&.{ glslc, "--target-env=vulkan1.1", "-O" });
            compile.addFileArg(b.path(shader.src));
            compile.addArg("-o");
            const output = compile.addOutputFileArg(shader.out);
            // 挂到 install：`run_cmd` 已 dependOn install，这样 `zig build run`
            // 一定会先把着色器编出来。
            const install = b.addInstallFile(output, b.fmt("shaders/{s}", .{shader.out}));
            b.getInstallStep().dependOn(&install.step);
            shaders_step.dependOn(&install.step);
        }
    }
}

/// 找 `glslc`：显式 `-Dglslc=` > PATH > `%VULKAN_SDK%\Bin\glslc.exe`。
fn resolveGlslc(b: *std.Build) []const u8 {
    if (b.option([]const u8, "glslc", "glslc 路径（Vulkan 着色器）")) |explicit| return explicit;
    if (b.findProgram(.{ .names = &.{"glslc"} })) |found| return found;
    if (b.graph.environ_map.get("VULKAN_SDK")) |sdk| {
        const candidate = b.pathJoin(&.{ sdk, "Bin", "glslc.exe" });
        if (fileExists(b, candidate)) return candidate;
    }
    @panic("找不到 glslc：安装 Vulkan SDK（shaderc），或用 -Dglslc=<path> 指定");
}

fn fileExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(b.graph.io, path, .{}) catch return false;
    return true;
}

/// 按目标组装引擎模块。
///
/// 引擎只依赖后端中立的 `render_types` 和已选定的 `render_backend`；
/// `win32` / `vulkan` 由对应后端模块自己带，不会漏到引擎的 import 表里。
fn createEngineModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    windowkit: *std.Build.Module,
    render_types: *std.Build.Module,
    render_backend: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "windowkit", .module = windowkit },
            .{ .name = "render_types", .module = render_types },
            .{ .name = "render_backend", .module = render_backend },
        },
    });
}
