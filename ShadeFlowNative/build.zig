const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

    const dll_copy_path = "../../ShadeFlowUI/";

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
