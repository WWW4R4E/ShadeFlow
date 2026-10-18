//! VkInstance + Wayland surface + 校验层。
//!
//! 加载方式：直接 `dlopen("libvulkan.so.1")` 取 `vkGetInstanceProcAddr`，
//! 不在链接期依赖 `libvulkan.so`（很多发行版只装运行时、没有 -dev 软链）。
//!
//! wrapper 按值保存在结构体里，不持有指向自身的指针，所以 `Instance` 可以
//! 安全地按值返回/移动。

const std = @import("std");

const vk = @import("vulkan");

const Types = @import("../../Types.zig");

pub const validation_layer_name = "VK_LAYER_KHRONOS_validation";

pub const Instance = struct {
    lib: std.DynLib,
    base: vk.BaseWrapper,
    wrapper: vk.InstanceWrapper,
    handle: vk.Instance,
    surface: vk.SurfaceKHR,
    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,

    /// 创建 instance 与 Wayland surface（Linux 专用）。
    pub fn init(native: Types.NativeWindow, enable_validation: bool) !Instance {
        const wayland = switch (native) {
            .wayland => |handles| handles,
            else => return error.UnsupportedNativeWindow,
        };

        var lib = try std.DynLib.open("libvulkan.so.1");
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

        var extension_names: [3][*:0]const u8 = undefined;
        var extension_count: usize = 0;
        extension_names[extension_count] = vk.instance_extensions.khr_surface.name.ptr;
        extension_count += 1;
        extension_names[extension_count] = vk.instance_extensions.khr_wayland_surface.name.ptr;
        extension_count += 1;
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

        const surface_info = vk.WaylandSurfaceCreateInfoKHR{
            .display = @ptrCast(wayland.display),
            .surface = @ptrCast(wayland.surface),
        };
        const surface = try wrapper.createWaylandSurfaceKHR(handle, &surface_info, null);
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
