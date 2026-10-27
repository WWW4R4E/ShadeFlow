//! ShadeFlowNative 构建脚本。
//!
//! 平台分支（与 windowkit 的构建方式一致：编译期按 target 组装模块）：
//! - Windows：`win32` + `windowkit`，产出 exe，`dll` 步骤额外产出给 WinUI 的 DLL；
//! - Linux：  只有 `windowkit`，渲染后端编译期选 Vulkan；
//! - macOS：  只有 `windowkit`（AppKit），渲染后端编译期选 Vulkan（MoltenVK），
//!            `app` 步骤额外打包 `ShadeFlow.app`。
//!
//! 后端实现本身也是独立模块：`render_backend` 指向 d3d12 或 vulkan，只有
//! 被选中的那个会进模块图。Windows 默认 D3D12 构建不会解析 vulkan-zig，也不会生成 `vk.zig`。
//!
//! 依赖按平台/后端懒加载：`build.zig.zon` 里 `win32` / `vulkan` 标了 `lazy = true`，
//! 只在 Windows（`win32`）/ 用 Vulkan（`vulkan`）的分支里经 `win32Module` /
//! `vulkanModule` 解析。非 Windows 目标既不登记也不拉取 zigwin32 —— 细节见
//! `笔记/Zig依赖按平台懒加载.md`。
//!
//! 步骤：
//! - `zig build`             当前目标的 exe
//! - `zig build run`         运行当前目标的 exe
//! - `zig build dll`         （仅 Windows）构建并复制 `ShadeFlowNative.dll`
//! - `zig build app`         （仅 macOS）打包 `zig-out/ShadeFlow.app`
//! - `zig build shaders`     着色器 → SPIR-V（Vulkan 后端），已挂进 install 步骤
//!
//! Windows 默认 D3D12；用 `zig build run -Dbackend=vulkan` 切到 Vulkan 后端。
//! macOS / Linux 只有 Vulkan；macOS 依赖 MoltenVK（brew install molten-vk 或
//! LunarG Vulkan SDK）。
//!
//! Vulkan 着色器需要 `glslc`（Vulkan SDK / shaderc）：
//! 按 `-Dglslc=<path>` → PATH → `%VULKAN_SDK%` 的顺序查找。

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const is_windows = target.result.os.tag == .windows;
    const is_macos = target.result.os.tag == .macos;
    if (!is_windows and !is_macos and target.result.os.tag != .linux) {
        @panic("只支持 Windows（D3D12/Vulkan）、Linux（Vulkan）与 macOS（Vulkan/MoltenVK）目标");
    }

    // Windows 二选一：默认 d3d12，`-Dbackend=vulkan` 切换。
    // Linux 固定 Vulkan（与 backend/mod.zig 的分支保持一致）。
    const windows_backend = b.option(
        []const u8,
        "backend",
        "Windows 渲染后端：d3d12（默认）或 vulkan（macOS/Linux 固定 vulkan）",
    ) orelse "d3d12";
    const valid_backends = [_][]const u8{ "d3d12", "vulkan" };
    for (valid_backends) |valid| {
        if (std.mem.eql(u8, windows_backend, valid)) break;
    } else {
        @panic("backend 只能是 d3d12 或 vulkan");
    }
    const use_vulkan = !is_windows or std.mem.eql(u8, windows_backend, "vulkan");

    const windowkit = b.dependency("windowkit", .{
        .target = target,
        .optimize = optimize,
    }).module("windowkit");

    // 后端中立的描述类型单独成模块：后端实现与引擎共享同一份类型，
    // 否则 `NativeWindow` 等跨边界类型会变成两个不同的类型。
    const render_types = b.createModule(.{
        .root_source_file = b.path("src/engine/render/Types.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 每个后端是一个独立模块，依赖只在它自己身上：
    // - d3d12 跟着 win32 走，Windows 上按 -Dbackend 二选一；
    // - vulkan 只在 `-Dbackend=vulkan`（或 Linux）时才创建。
    //
    // `win32` / `vulkan` 在 build.zig.zon 里标了 `lazy = true`：只有走到这里
    // （Windows / 用 Vulkan 的构建）才会去解析它们，别的平台连依赖登记都不会发生。
    const d3d12_backend: ?*std.Build.Module = if (is_windows and std.mem.eql(u8, windows_backend, "d3d12")) blk: {
        const win32 = win32Module(b) orelse return;
        break :blk b.createModule(.{
            .root_source_file = b.path("src/engine/render/backend/d3d12/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "win32", .module = win32 },
                .{ .name = "render_types", .module = render_types },
            },
        });
    } else null;

    const vulkan_backend: ?*std.Build.Module = if (use_vulkan) blk: {
        const vulkan_mod = vulkanModule(b, optimize) orelse return;
        var imports: [3]std.Build.Module.Import = undefined;
        var count: usize = 0;
        imports[count] = .{ .name = "vulkan", .module = vulkan_mod };
        count += 1;
        imports[count] = .{ .name = "render_types", .module = render_types };
        count += 1;
        // Windows 上 loader 走 kernel32 的 LoadLibraryA/GetProcAddress。
        if (is_windows) {
            imports[count] = .{ .name = "win32", .module = win32Module(b) orelse return };
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
    const render_backend = if (use_vulkan)
        vulkan_backend.?
    else
        d3d12_backend.?;

    // 跨平台引擎模块（exe 用）。Linux 分支不引入 win32。
    const engine_mod = createEngineModule(
        b,
        target,
        optimize,
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
                .{ .name = "shadeflow_engine", .module = engine_mod },
                // 窗口与输入在宿主侧（src/host/），引擎本身不需要 windowkit。
                .{ .name = "windowkit", .module = windowkit },
            },
        }),
    });
    b.installArtifact(exe);

    // 样例模型：装到 zig-out/assets/models/（main.zig 按 exe 目录相对定位，
    // 与 shaders/ 同一套查找逻辑）。
    const sample_model = b.addInstallFile(
        b.path("assets/models/SampleBox.gltf"),
        "assets/models/SampleBox.gltf",
    );
    b.getInstallStep().dependOn(&sample_model.step);

    const sample_texture = b.addInstallFile(
        b.path("assets/textures/SampleTexture.jpg"),
        "assets/textures/SampleTexture.jpg",
    );
    b.getInstallStep().dependOn(&sample_texture.step);

    const wallpaper_texture = b.addInstallFile(
        b.path("assets/textures/Wallpaper.jpg"),
        "assets/textures/Wallpaper.jpg",
    );
    b.getInstallStep().dependOn(&wallpaper_texture.step);

    const box_textured_model = b.addInstallFile(
        b.path("assets/models/BoxTextured.glb"),
        "assets/models/BoxTextured.glb",
    );
    b.getInstallStep().dependOn(&box_textured_model.step);

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
            "WinUI Composition 模式只支持 D3D 后端；Vulkan 后端请用 zig build run -Dbackend=vulkan",
        ).step);
    } else if (is_windows) {
        const dll_copy_path = "../../ShadeFlowUI/";
        const capi_mod = b.createModule(.{
            .root_source_file = b.path("src/capi.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "win32", .module = win32Module(b) orelse return },
                // 引擎本身作为命名模块导入（`@import("shadeflow_engine")`），
                // 它内部的 render_types / render_backend 由引擎模块自己带。
                .{ .name = "shadeflow_engine", .module = engine_mod },
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
    const ShaderArtifact = struct {
        name: []const u8,
        output: std.Build.LazyPath,
    };
    var shader_artifacts: [4]ShaderArtifact = undefined;
    var shader_count: usize = 0;
    if (use_vulkan) {
        const glslc = resolveGlslc(b);
        const glsl_sources = [_]struct { src: []const u8, out: []const u8 }{
            .{ .src = "assets/shaders/Basic3D.vert", .out = "Basic3DVS.spv" },
            .{ .src = "assets/shaders/Basic3D.frag", .out = "Basic3DPS.spv" },
            .{ .src = "assets/shaders/Basic3DTextured.vert", .out = "Basic3DTexturedVS.spv" },
            .{ .src = "assets/shaders/Basic3DTextured.frag", .out = "Basic3DTexturedPS.spv" },
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

            shader_artifacts[shader_count] = .{ .name = shader.out, .output = output };
            shader_count += 1;
        }
    }

    // 单元测试。两个测试目标：
    //
    // - `src/tests.zig`：宿主侧输入状态 + 引擎侧纯数学（Aabb / Matrix / Picker）。
    //   它会链上当前平台的渲染后端，但测试只跑数学，不碰 GPU。
    // - `src/engine/render/Types.zig`：`render_types` 是独立模块，它的测试
    //   不会被上面的根模块收进来，单独跑一个目标。
    //
    // 资源导入（asset/）落地后，glTF / PNG 解析器的测试会加进第一个目标。
    const test_step = b.step("test", "Run unit tests");

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "windowkit", .module = windowkit },
            .{ .name = "render_types", .module = render_types },
            .{ .name = "render_backend", .module = render_backend },
            // tests.zig 相对 import engine/asset/ 下的解析器，它们的
            // @import("zigimg") 落到这个模块的 import 表上。
            .{ .name = "zigimg", .module = b.dependency("zigimg", .{}).module("zigimg") },
        },
    });
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tests.step);

    const types_test_mod = b.createModule(.{
        .root_source_file = b.path("src/engine/render/Types.zig"),
        .target = target,
        .optimize = optimize,
    });
    const types_tests = b.addTest(.{ .root_module = types_test_mod });
    const run_types_tests = b.addRunArtifact(types_tests);
    test_step.dependOn(&run_types_tests.step);

    // macOS 应用包：Finder 双击 / Gatekeeper / Dock 都按 bundle 识别。
    // 布局与 main.zig 的着色器查找顺序对应：
    //   ShadeFlow.app/Contents/MacOS/ShadeFlowNative
    //   ShadeFlow.app/Contents/Resources/shaders/*.spv
    const app_step = b.step("app", "Build ShadeFlow.app bundle (macOS only)");
    if (is_macos) {
        const app_name = "ShadeFlow.app";
        const macos_exe = b.addInstallFileWithDir(
            exe.getEmittedBin(),
            .prefix,
            b.fmt("{s}/Contents/MacOS/ShadeFlowNative", .{app_name}),
        );
        app_step.dependOn(&macos_exe.step);

        const plist = b.addWriteFiles().add("Info.plist", macos_info_plist);
        const install_plist = b.addInstallFileWithDir(
            plist,
            .prefix,
            b.fmt("{s}/Contents/Info.plist", .{app_name}),
        );
        app_step.dependOn(&install_plist.step);

        for (shader_artifacts[0..shader_count]) |artifact| {
            const install = b.addInstallFileWithDir(
                artifact.output,
                .prefix,
                b.fmt("{s}/Contents/Resources/shaders/{s}", .{ app_name, artifact.name }),
            );
            app_step.dependOn(&install.step);
        }
    } else {
        app_step.dependOn(&b.addFail("ShadeFlow.app 只能在 macOS 上打包").step);
    }

    // macOS 交叉类型检查：只 emit object，不进链接器，所以 Linux/Windows
    // 主机没有 macOS SDK 也能验证 AppKit + MoltenVK 这条分支（与 windowkit
    // 自身的 `typecheck-macos` 思路一致）。
    //
    // 注意不能直接复用 `b.dependency("windowkit").module("windowkit")`：窗口库
    // 注册的模块始终带 linkFramework，build-obj 也会触发框架查找。这里按它
    // build.zig 的 macOS 分支手装一份不链接的模块。
    //
    // Windows 默认 D3D12 构建不解析 vulkan-zig（见上），所以这个步骤只在
    // 已经选了 Vulkan 后端时可用。
    const typecheck_step = b.step(
        "typecheck-macos",
        "Analyze the macOS backend from any host (object only, no linking)",
    );
    if (use_vulkan) {
        const typecheck_target = b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos });
        const typecheck_windowkit_dep = b.dependency("windowkit", .{
            .target = typecheck_target,
            .optimize = optimize,
        });
        const typecheck_objc = b.createModule(.{
            .root_source_file = typecheck_windowkit_dep.path("src/platform/macos/objc/main.zig"),
            .target = typecheck_target,
            .optimize = optimize,
        });
        const typecheck_windowkit = b.createModule(.{
            .root_source_file = typecheck_windowkit_dep.path("src/root.zig"),
            .target = typecheck_target,
            .optimize = optimize,
            .imports = &.{.{ .name = "objc", .module = typecheck_objc }},
        });
        const typecheck_render_types = b.createModule(.{
            .root_source_file = b.path("src/engine/render/Types.zig"),
            .target = typecheck_target,
            .optimize = optimize,
        });
        const typecheck_render_backend = b.createModule(.{
            .root_source_file = b.path("src/engine/render/backend/vulkan/mod.zig"),
            .target = typecheck_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vulkan", .module = vulkanModule(b, optimize) orelse return },
                .{ .name = "render_types", .module = typecheck_render_types },
            },
        });
        const typecheck_engine = createEngineModule(
            b,
            typecheck_target,
            optimize,
            typecheck_render_types,
            typecheck_render_backend,
        );
        const typecheck_exe = b.addObject(.{
            .name = "ShadeFlowNative-macos-typecheck",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = typecheck_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "shadeflow_engine", .module = typecheck_engine },
                    .{ .name = "windowkit", .module = typecheck_windowkit },
                },
            }),
        });
        typecheck_step.dependOn(&typecheck_exe.step);
    } else {
        typecheck_step.dependOn(&b.addFail(
            "typecheck-macos 需要 Vulkan 绑定：Windows 上请加 -Dbackend=vulkan",
        ).step);
    }
}

/// `zig build app` 写入的 Info.plist。
const macos_info_plist =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    \\<plist version="1.0">
    \\<dict>
    \\    <key>CFBundleName</key>
    \\    <string>ShadeFlow</string>
    \\    <key>CFBundleDisplayName</key>
    \\    <string>ShadeFlow</string>
    \\    <key>CFBundleIdentifier</key>
    \\    <string>dev.shadeflow.native</string>
    \\    <key>CFBundleExecutable</key>
    \\    <string>ShadeFlowNative</string>
    \\    <key>CFBundlePackageType</key>
    \\    <string>APPL</string>
    \\    <key>CFBundleShortVersionString</key>
    \\    <string>0.1.0</string>
    \\    <key>CFBundleVersion</key>
    \\    <string>1</string>
    \\    <key>LSMinimumSystemVersion</key>
    \\    <string>13.0</string>
    \\    <key>NSHighResolutionCapable</key>
    \\    <true/>
    \\</dict>
    \\</plist>
    \\
;

/// 找 `glslc`：显式 `-Dglslc=` > PATH > Vulkan SDK 的 bin 目录。
///
/// 找不到时不在这里 panic：`typecheck-macos` 这类步骤不需要着色器，
/// 让错误只在真正执行编译命令的步骤（install / shaders / app）上出现。
fn resolveGlslc(b: *std.Build) []const u8 {
    if (b.option([]const u8, "glslc", "glslc 路径（Vulkan 着色器）")) |explicit| return explicit;
    if (b.findProgram(.{ .names = &.{"glslc"} })) |found| return found;
    if (b.graph.environ_map.get("VULKAN_SDK")) |sdk| {
        // Windows SDK 是 Bin/glslc.exe；Linux/macOS SDK 是 bin/glslc。
        const candidates = [_][]const u8{
            b.pathJoin(&.{ sdk, "Bin", "glslc.exe" }),
            b.pathJoin(&.{ sdk, "bin", "glslc" }),
        };
        for (candidates) |candidate| {
            if (fileExists(b, candidate)) return candidate;
        }
    }
    std.log.warn(
        "找不到 glslc：Vulkan 着色器构建会失败。安装 Vulkan SDK / shaderc，或用 -Dglslc=<path> 指定",
        .{},
    );
    return "glslc";
}

fn fileExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(b.graph.io, path, .{}) catch return false;
    return true;
}

/// `zigwin32` 的绑定模块。只在 Windows 分支里调用（`build.zig.zon` 里它标了
/// `lazy = true`，非 Windows 目标不引用就不会被登记、不会被拉取）。
///
/// 返回 null 表示这个包当前还没拉取 —— `lazyDependency` 已经顺手把需求登记进
/// `needed_lazy_dependencies`；调用方 `orelse return` 结束本次配置，工具链拉完
/// 这个包后会重新跑一遍 `build.zig`，第二次就能拿到真正的 module。
fn win32Module(b: *std.Build) ?*std.Build.Module {
    const dep = b.lazyDependency("win32", .{}) orelse return null;
    return dep.module("win32");
}

/// `vulkan-zig` 的绑定模块（会用 `vendor/vk.xml` 生成 `vk.zig`）。只在确实要用
/// Vulkan 时调用，理由与 `win32Module` 相同，zon 里同样是 `lazy = true`。
fn vulkanModule(b: *std.Build, optimize: std.builtin.OptimizeMode) ?*std.Build.Module {
    const dep = b.lazyDependency("vulkan", .{
        .registry = b.path("vendor/vk.xml"),
        .optimize = optimize,
    }) orelse return null;
    return dep.module("vulkan-zig");
}

/// 按目标组装引擎模块。
///
/// 引擎只依赖后端中立的 `render_types` 和已选定的 `render_backend`；
/// `win32` / `vulkan` 由对应后端模块自己带，不会漏到引擎的 import 表里。
///
/// 引擎**不依赖 windowkit**：窗口与输入在宿主侧（`src/host/`），宿主通过
/// 引擎的命令入口驱动它。这样 Composition 模式（`capi.zig`）的 DLL 不会
/// 白链接一套窗口库。
fn createEngineModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    render_types: *std.Build.Module,
    render_backend: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/engine/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "render_types", .module = render_types },
            .{ .name = "render_backend", .module = render_backend },
            // 资源加载（engine/asset/）：glTF 用 std.json，PNG 用 zigimg。
            // 跨平台纯 Zig，不是 lazy 依赖，所有目标都会拉取。
            .{ .name = "zigimg", .module = b.dependency("zigimg", .{}).module("zigimg") },
        },
    });
}
