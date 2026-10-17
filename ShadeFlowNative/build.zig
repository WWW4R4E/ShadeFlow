//! ShadeFlowNative 构建脚本。
//!
//! 平台分支（与 windowkit 的构建方式一致：编译期按 target 组装模块）：
//! - Windows：`win32` + `windowkit`，产出 exe，`dll` 步骤额外产出给 WinUI 的 DLL；
//! - Linux：  只有 `windowkit`，渲染后端编译期选 Vulkan（当前是骨架）。
//!
//! 步骤：
//! - `zig build`             当前目标的 exe
//! - `zig build run`         运行当前目标的 exe
//! - `zig build dll`         （仅 Windows）构建并复制 `ShadeFlowNative.dll` 到 UI 项目
//! - `zig build typecheck-linux`  从任意主机分析 Linux 分支（只出 object，不链接）

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const is_windows = target.result.os.tag == .windows;

    // 共享的引擎模块。imports 按平台不同：Linux 分支不引入 win32。
    const engine_mod = createEngineModule(b, target, optimize, is_windows);

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

    // dll 步骤：只有 Windows 有 WinUI 宿主，其他平台明确失败而不是假装成功。
    const dll_step = b.step("dll", "Build DLL and copy to ShadeFlowUI (Windows only)");
    if (is_windows) {
        const dll_copy_path = "../../ShadeFlowUI/";
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "ShadeFlowNative",
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .root_module = engine_mod,
        });
        b.installArtifact(lib);

        const install_dll = b.addInstallFile(lib.getEmittedBin(), b.fmt("{s}/ShadeFlowNative.dll", .{dll_copy_path}));
        dll_step.dependOn(&install_dll.step);
    } else {
        dll_step.dependOn(&b.addFail("ShadeFlowNative.dll 只用于 Windows 上的 WinUI 3 宿主").step);
    }

    // Linux 分支交叉分析：只分析 render/（含 Vulkan 骨架），不进链接器，也不
    // 引入 windowkit（否则会要求本机有 wayland-client）。完整 Linux 构建请在
    // Linux 上直接 `zig build`。
    const linux_target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux });
    const linux_render = b.createModule(.{
        .root_source_file = b.path("src/engine/render/root.zig"),
        .target = linux_target,
        .optimize = optimize,
    });
    const linux_obj = b.addObject(.{
        .name = "typecheck-linux",
        .root_module = linux_render,
    });

    const typecheck_linux = b.step(
        "typecheck-linux",
        "Analyze the Linux/Vulkan branch from any host (object only, no linking)",
    );
    typecheck_linux.dependOn(&linux_obj.step);
}

/// 按目标组装引擎模块。
///
/// `win32` 只在 Windows 目标的 imports 里出现；Linux 分支连模块名都看不到，
/// 从根上避免 `@import("win32")` 被误分析。
fn createEngineModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    with_win32: bool,
) *std.Build.Module {
    const windowkit = b.dependency("windowkit", .{
        .target = target,
        .optimize = optimize,
    }).module("windowkit");

    const imports: []const std.Build.Module.Import = if (with_win32)
        &.{
            .{ .name = "win32", .module = b.dependency("win32", .{}).module("win32") },
            .{ .name = "windowkit", .module = windowkit },
        }
    else
        &.{
            .{ .name = "windowkit", .module = windowkit },
        };

    return b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    });
}
