// const std = @import("std");

// pub fn build(b: *std.Build) void {
//     const target = b.standardTargetOptions(.{});
//     const optimize = b.standardOptimizeOption(.{});
//     const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

//     const mod = b.addModule("ShadeFlowNative", .{
//         .root_source_file = b.path("src/root.zig"),
//         .target = target,
//         .optimize = optimize,
//         .imports = &.{
//             .{ .name = "win32", .module = zigwin32 },
//         },
//     });
//     const exe = b.addExecutable(.{
//         .name = "ShadeFlowNative",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("src/main.zig"),
//             .target = target,
//             .optimize = optimize,
//             .imports = &.{
//                 .{ .name = "ShadeFlowNative", .module = mod },
//                 .{ .name = "win32", .module = zigwin32 },
//             },
//         }),
//     });

//     b.installArtifact(exe);

//     const lib = b.addLibrary(.{
//         .linkage = .dynamic,
//         .name = "ShadeFlowNative",
//         .version = .{ .major = 1, .minor = 0, .patch = 0 },
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("src/root.zig"),
//             .target = target,
//             .optimize = optimize,
//             .imports = &.{
//                 .{ .name = "ShadeFlowNative", .module = mod },
//                 .{ .name = "win32", .module = zigwin32 },
//             },
//         }),
//     });

//     b.installArtifact(lib);

//     const run_step = b.step("run", "Run the app");

//     const run_cmd = b.addRunArtifact(exe);
//     run_step.dependOn(&run_cmd.step);

//     run_cmd.step.dependOn(b.getInstallStep());

//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }

//     const mod_tests = b.addTest(.{
//         .root_module = mod,
//     });

//     const run_mod_tests = b.addRunArtifact(mod_tests);

//     const exe_tests = b.addTest(.{
//         .root_module = exe.root_module,
//     });

//     const run_exe_tests = b.addRunArtifact(exe_tests);

//     const test_step = b.step("test", "Run tests");
//     test_step.dependOn(&run_mod_tests.step);
//     test_step.dependOn(&run_exe_tests.step);

//     // 添加内存泄漏检测步骤
//     const leak_check_options = b.addOptions();

//     // 启用DebugAllocator进行内存泄漏检测
//     const debug_gpa = b.option(bool, "debug-allocator", "Force the compiler to use DebugAllocator") orelse true; // 默认启用
//     leak_check_options.addOption(bool, "debug_gpa", debug_gpa);

//     // 配置内存泄漏堆栈帧数量
//     const mem_leak_frames: u32 = b.option(u32, "mem-leak-frames", "How many stack frames to print when a memory leak occurs.") orelse 8;
//     leak_check_options.addOption(u32, "mem_leak_frames", mem_leak_frames);

//     // 先创建模块 - 正确的方式
//     const leak_check_module = b.createModule(.{
//         .root_source_file = b.path("src/root.zig"),
//         .target = target,
//         .optimize = .Debug,
//         .imports = &.{
//             .{ .name = "ShadeFlowNative", .module = mod },
//             .{ .name = "win32", .module = zigwin32 },
//         },
//     });

//     // 将选项添加到模块
//     leak_check_module.addOptions("build_options", leak_check_options);

//     // 然后创建库并设置root_module
//     const leak_check_lib = b.addLibrary(.{
//         .linkage = .dynamic,
//         .name = "ShadeFlowNative",
//         .root_module = leak_check_module,
//         .version = .{ .major = 1, .minor = 0, .patch = 0 },
//     });

//     // 创建leak_check步骤
//     const leak_check_step = b.step("leak_check", "Build with memory leak detection");
//     leak_check_step.dependOn(&leak_check_lib.step);

//     // 安装构建结果
//     b.installArtifact(leak_check_lib);
// }
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

    // 在这里设置DLL的目标复制路径
    const dll_copy_path = "C:/YourProject/bin"; // 修改为你的实际路径

    // 创建共享的根模块
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = zigwin32 },
        },
    });

    // 构建EXE(默认)
    const exe = b.addExecutable(.{
        .name = "ShadeFlowNative",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ShadeFlowNative", .module = root_module },
                .{ .name = "win32", .module = zigwin32 },
            },
        }),
    });
    b.installArtifact(exe);

    // run步骤 - 默认运行exe
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    // dll步骤 - 构建并复制DLL
    const dll_step = b.step("dll", "Build DLL and copy to target path");
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "ShadeFlowNative",
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .root_module = root_module,
    });
    b.installArtifact(lib);

    // 复制DLL到指定路径
    const install_dll = b.addInstallFile(lib.getEmittedBin(), b.fmt("{s}/ShadeFlowNative.dll", .{dll_copy_path}));
    dll_step.dependOn(&install_dll.step);

    // 测试步骤
    const lib_tests = b.addTest(.{
        .root_module = root_module,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // 如果需要更多测试,可以添加
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const exe_test_step = b.step("test-exe", "Run executable tests");
    exe_test_step.dependOn(&run_exe_tests.step);
}
