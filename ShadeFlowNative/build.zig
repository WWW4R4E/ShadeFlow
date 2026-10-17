const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dll_copy_path = "../../ShadeFlowUI/";
    const win32 = b.dependency("win32", .{}).module("win32");
    const windowkit = b.dependency("windowkit", .{}).module("windowkit");
    // 创建共享的根模块
    const mod = b.addModule("ShadeFlowNative", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = win32 },
            .{ .name = "windowkit", .module = windowkit },
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
                .{ .name = "ShadeFlowNative", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    // run步骤 - 默认运行exe
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

    // dll步骤 - 构建并复制DLL
    const dll_step = b.step("dll", "Build DLL and copy to target path");
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "ShadeFlowNative",
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .root_module = mod,
    });
    b.installArtifact(lib);

    // 复制DLL到指定路径
    const install_dll = b.addInstallFile(lib.getEmittedBin(), b.fmt("{s}/ShadeFlowNative.dll", .{dll_copy_path}));
    dll_step.dependOn(&install_dll.step);
}
