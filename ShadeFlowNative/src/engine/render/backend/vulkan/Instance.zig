//! VkInstance + 平台 surface（Windows/Win32、Linux/Wayland、macOS/Metal）+ 校验层。
//!
//! 加载方式：运行时加载 Vulkan 实现并取 `vkGetInstanceProcAddr`，不在链接期
//! 依赖 `vulkan-1.lib` / `libvulkan.so` / `libMoltenVK.dylib`。
//!
//! - Linux：`std.DynLib` + `libvulkan.so.1`（很多发行版只装运行时、没有 -dev 软链）。
//! - Windows：`std.DynLib` 没有 Windows 实现，改走 kernel32 的
//!   `LoadLibraryA("vulkan-1.dll")` + `GetProcAddress`。
//! - macOS：没有系统 Vulkan。优先用 MoltenVK（`libMoltenVK.dylib`，它自带
//!   Vulkan 入口，不经过 loader），再试 Vulkan SDK / Homebrew 的 loader。
//!   surface 走 `VK_EXT_metal_surface`，直接包 windowkit 交出的 `CAMetalLayer`。
//!
//! wrapper 按值保存在结构体里，不持有指向自身的指针，所以 `Instance` 可以
//! 安全地按值返回/移动。

const std = @import("std");
const builtin = @import("builtin");

const vk = @import("vulkan");

const Types = @import("render_types");

/// 只有 Windows 目标会分析 `WindowsLoader`；其他平台的 `win32` 是空占位，
/// 保证不需要 win32 模块。
const win32 = if (builtin.os.tag == .windows) @import("win32").everything else struct {};

pub const validation_layer_name = "VK_LAYER_KHRONOS_validation";

/// 各平台的动态库候选名（按顺序尝试，先命中先返回）。
///
/// macOS 顺序：MoltenVK 本体优先（最省事，不依赖 ICD 配置），再是 LunarG
/// SDK / Homebrew 的 loader；`VULKAN_SDK` 下的绝对路径由 `openLoader` 追加。
const loader_names: []const [:0]const u8 = switch (builtin.os.tag) {
    .windows => &.{"vulkan-1.dll"},
    .linux => &.{ "libvulkan.so.1", "libvulkan.so" },
    .macos => &.{
        "libMoltenVK.dylib",
        "libvulkan.1.dylib",
        "libvulkan.dylib",
        "/opt/homebrew/lib/libMoltenVK.dylib",
        "/usr/local/lib/libMoltenVK.dylib",
        "/opt/homebrew/lib/libvulkan.1.dylib",
        "/usr/local/lib/libvulkan.1.dylib",
    },
    else => @compileError("Vulkan 后端只支持 Windows / Linux / macOS"),
};

/// `std.DynLib` 在 Windows 上是 `@compileError`，这里按平台换实现。
const Loader = if (builtin.os.tag == .windows) WindowsLoader else std.DynLib;

const WindowsLoader = struct {
    handle: win32.HINSTANCE,

    fn openZ(path: [*:0]const u8) !WindowsLoader {
        const handle = win32.LoadLibraryA(path) orelse return error.FileNotFound;
        return .{ .handle = handle };
    }

    fn close(self: *WindowsLoader) void {
        _ = win32.FreeLibrary(self.handle);
        self.* = undefined;
    }

    fn lookup(self: *WindowsLoader, comptime T: type, name: [:0]const u8) ?T {
        const proc = win32.GetProcAddress(self.handle, name.ptr) orelse return null;
        return @as(T, @ptrFromInt(@intFromPtr(proc)));
    }
};

/// 依次尝试 `loader_names`，失败时把最后一次错误往上抛。
///
/// macOS 额外查 `$VULKAN_SDK/lib`：LunarG SDK 不会把 dylib 加进 dyld 搜索
/// 路径，用户通常也没设 `DYLD_LIBRARY_PATH`。
fn openLoader() !Loader {
    if (builtin.os.tag == .windows) return WindowsLoader.openZ("vulkan-1.dll");
    return openPosixLoader();
}

/// Linux/macOS 共用：`std.DynLib` + 候选名（Windows 分支不会分析到这里）。
fn openPosixLoader() !Loader {
    var last_error: anyerror = error.FileNotFound;

    for (loader_names) |name| {
        if (std.DynLib.openZ(name)) |lib| {
            return lib;
        } else |err| {
            last_error = err;
        }
    }

    if (builtin.os.tag == .macos) {
        if (std.c.getenv("VULKAN_SDK")) |sdk_z| {
            const sdk = std.mem.span(sdk_z);
            var buffer: [std.fs.max_path_bytes]u8 = undefined;
            const candidates = [_][]const u8{
                "lib/libMoltenVK.dylib",
                "lib/libvulkan.1.dylib",
                "lib/libvulkan.dylib",
            };
            for (candidates) |suffix| {
                const path = std.fmt.bufPrintSentinel(&buffer, "{s}/{s}", .{ sdk, suffix }, 0) catch continue;
                if (std.DynLib.openZ(path)) |lib| {
                    return lib;
                } else |err| {
                    last_error = err;
                }
            }
        }
    }

    std.log.err(
        "找不到 Vulkan 实现（试过 {d} 个候选）。macOS 请安装 MoltenVK：brew install molten-vk，或安装 LunarG Vulkan SDK 并设置 VULKAN_SDK",
        .{loader_names.len},
    );
    return last_error;
}

pub const Instance = struct {
    lib: Loader,
    base: vk.BaseWrapper,
    wrapper: vk.InstanceWrapper,
    handle: vk.Instance,
    surface: vk.SurfaceKHR,
    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,

    /// 创建 instance 与平台 surface（Windows: Win32；Linux: Wayland；macOS: Metal）。
    pub fn init(native: Types.NativeWindow, enable_validation: bool) !Instance {
        // 先确认窗口类型，再决定要启用哪个 surface 扩展。
        const surface_extension: [:0]const u8 = switch (native) {
            // vulkan-zig 把扩展名拆成 khr_win_32_surface，别依赖这个拼写，直接写字面量。
            .win32 => "VK_KHR_win32_surface",
            .wayland => vk.instance_extensions.khr_wayland_surface.name,
            // MoltenVK 的推荐 surface：直接包 CAMetalLayer（旧的 MVK_macos_surface 已废弃）。
            .appkit => vk.instance_extensions.ext_metal_surface.name,
            else => return error.UnsupportedNativeWindow,
        };

        var lib = try openLoader();
        errdefer lib.close();

        const get_proc_addr = lib.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse
            return error.VulkanLoaderUnavailable;
        const base = vk.BaseWrapper.load(get_proc_addr);

        const allocator = std.heap.page_allocator;

        // 校验层：有就开、没有就降级（与 D3D11 的 debug layer 策略一致）。
        const validation = enable_validation and try hasLayer(base, validation_layer_name, allocator);
        if (enable_validation and !validation) {
            std.log.warn("未找到 VK_LAYER_KHRONOS_validation，Vulkan 校验层已禁用", .{});
        }

        const debug_utils = validation and try hasInstanceExtension(
            base,
            vk.instance_extensions.ext_debug_utils.name,
            allocator,
        );

        // MoltenVK 属于 portability 实现：必须显式启用并设置枚举标志，
        // 否则 vkEnumeratePhysicalDevices 可能一台设备都看不到。
        const portability = try hasInstanceExtension(
            base,
            vk.instance_extensions.khr_portability_enumeration.name,
            allocator,
        );

        var extension_names: [4][*:0]const u8 = undefined;
        var extension_count: usize = 0;
        extension_names[extension_count] = vk.instance_extensions.khr_surface.name.ptr;
        extension_count += 1;
        extension_names[extension_count] = surface_extension.ptr;
        extension_count += 1;
        if (portability) {
            extension_names[extension_count] = vk.instance_extensions.khr_portability_enumeration.name.ptr;
            extension_count += 1;
        }
        if (debug_utils) {
            extension_names[extension_count] = vk.instance_extensions.ext_debug_utils.name.ptr;
            extension_count += 1;
        }

        var layer_names: [1][*:0]const u8 = undefined;
        if (validation) layer_names[0] = validation_layer_name;

        const app_info = vk.ApplicationInfo{
            .p_application_name = "ShadeFlow",
            .application_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
            .p_engine_name = "ShadeFlowNative",
            .engine_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
            // 1.1：负高度 viewport（Y 翻转）在 1.1 起是核心能力。
            .api_version = vk.makeApiVersion(0, 1, 1, 0).toU32(),
        };

        const create_info = vk.InstanceCreateInfo{
            .flags = .{ .enumerate_portability_khr = portability },
            .p_application_info = &app_info,
            .enabled_layer_count = if (validation) 1 else 0,
            .pp_enabled_layer_names = if (validation) &layer_names else null,
            .enabled_extension_count = @intCast(extension_count),
            .pp_enabled_extension_names = &extension_names,
        };

        const handle = try base.createInstance(&create_info, null);
        // 这版 vulkan-zig 的 destroyInstance 在 InstanceWrapper 上，BaseWrapper 没有，
        // 所以 errdefer 必须排在 wrapper 创建之后。
        const wrapper = vk.InstanceWrapper.load(handle, get_proc_addr);
        errdefer wrapper.destroyInstance(handle, null);

        const surface = switch (native) {
            .win32 => |handles| blk: {
                const surface_info = vk.Win32SurfaceCreateInfoKHR{
                    .hinstance = @ptrCast(handles.hinstance),
                    .hwnd = @ptrCast(handles.hwnd),
                };
                break :blk try wrapper.createWin32SurfaceKHR(handle, &surface_info, null);
            },
            .wayland => |handles| blk: {
                const surface_info = vk.WaylandSurfaceCreateInfoKHR{
                    .display = @ptrCast(handles.display),
                    .surface = @ptrCast(handles.surface),
                };
                break :blk try wrapper.createWaylandSurfaceKHR(handle, &surface_info, null);
            },
            .appkit => |handles| blk: {
                const surface_info = vk.MetalSurfaceCreateInfoEXT{
                    .p_layer = @ptrCast(handles.metal_layer),
                };
                break :blk try wrapper.createMetalSurfaceEXT(handle, &surface_info, null);
            },
            else => unreachable,
        };
        errdefer wrapper.destroySurfaceKHR(handle, surface, null);

        var debug_messenger: ?vk.DebugUtilsMessengerEXT = null;
        if (debug_utils) {
            const messenger_info = vk.DebugUtilsMessengerCreateInfoEXT{
                .message_severity = .{
                    .verbose_ext = false,
                    .info_ext = true,
                    .warning_ext = true,
                    .error_ext = true,
                },
                .message_type = .{
                    .general_ext = true,
                    .validation_ext = true,
                    .performance_ext = true,
                },
                .pfn_user_callback = debugCallback,
            };
            debug_messenger = try wrapper.createDebugUtilsMessengerEXT(handle, &messenger_info, null);
        }

        return .{
            .lib = lib,
            .base = base,
            .wrapper = wrapper,
            .handle = handle,
            .surface = surface,
            .debug_messenger = debug_messenger,
        };
    }

    pub fn deinit(self: *Instance) void {
        if (self.debug_messenger) |messenger| {
            self.wrapper.destroyDebugUtilsMessengerEXT(self.handle, messenger, null);
        }
        self.wrapper.destroySurfaceKHR(self.handle, self.surface, null);
        self.wrapper.destroyInstance(self.handle, null);
        self.lib.close();
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn hasLayer(base: vk.BaseWrapper, name: []const u8, allocator: std.mem.Allocator) !bool {
        const properties = base.enumerateInstanceLayerPropertiesAlloc(allocator) catch |err| {
            std.log.warn("枚举 Vulkan 层失败: {s}", .{@errorName(err)});
            return false;
        };
        defer allocator.free(properties);

        for (properties) |property| {
            if (std.mem.eql(u8, std.mem.sliceTo(&property.layer_name, 0), name)) return true;
        }
        return false;
    }

    fn hasInstanceExtension(base: vk.BaseWrapper, name: []const u8, allocator: std.mem.Allocator) !bool {
        const properties = base.enumerateInstanceExtensionPropertiesAlloc(null, allocator) catch |err| {
            std.log.warn("枚举 Vulkan 实例扩展失败: {s}", .{@errorName(err)});
            return false;
        };
        defer allocator.free(properties);

        for (properties) |property| {
            if (std.mem.eql(u8, std.mem.sliceTo(&property.extension_name, 0), name)) return true;
        }
        return false;
    }

    fn debugCallback(
        severity: vk.DebugUtilsMessageSeverityFlagsEXT,
        message_type: vk.DebugUtilsMessageTypeFlagsEXT,
        callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
        user_data: ?*anyopaque,
    ) callconv(vk.vulkan_call_conv) vk.Bool32 {
        _ = message_type;
        _ = user_data;

        const message = if (callback_data) |data|
            if (data.p_message) |text| std.mem.span(text) else "(无消息)"
        else
            "(无回调数据)";

        if (severity.error_ext) {
            std.log.err("[vulkan] {s}", .{message});
        } else if (severity.warning_ext) {
            std.log.warn("[vulkan] {s}", .{message});
        } else {
            std.log.info("[vulkan] {s}", .{message});
        }

        return .false;
    }
};
