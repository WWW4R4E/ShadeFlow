//! 交换链：VkSwapchainKHR + 图像视图 + render pass + 深度图 + framebuffer。
//!
//! 交换链相关的查询（capabilities / formats / present modes）走的是
//! **Instance** 的函数（`vkGetPhysicalDeviceSurface*`），而 `Renderer` 是按值
//! 移动的，所以这些函数指针不能存进 `SwapChain`——调用时由 `Renderer` 传进来。
//! `SwapChain` 只留 `surface` 与 `physical_device` 这类稳定的句柄。

const std = @import("std");

const vk = @import("vulkan");

const Device = @import("Device.zig").Device;
const Instance = @import("Instance.zig").Instance;

/// present 模式：与 D3D11 后端的 `Present(1, 0)` 对齐，用 FIFO（垂直同步）。
const preferred_present_mode: vk.PresentModeKHR = .fifo_khr;

pub const SwapChain = struct {
    shared: *const Device.Shared,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,

    handle: vk.SwapchainKHR = .null,
    format: vk.Format = .b8g8r8a8_unorm,
    depth_format: vk.Format = .d32_sfloat,
    extent: vk.Extent2D = .{ .width = 0, .height = 0 },

    images: []vk.Image = &.{},
    views: []vk.ImageView = &.{},
    framebuffers: []vk.Framebuffer = &.{},

    render_pass: vk.RenderPass = .null,

    depth_image: vk.Image = .null,
    depth_memory: vk.DeviceMemory = .null,
    depth_view: vk.ImageView = .null,

    /// 建/重建交换链需要的东西：设备侧句柄 + 物理设备 + instance（surface 查询）。
    ///
    /// 作为参数传入而不是存在 `SwapChain` 里：`Renderer` 是按值移动的，
    /// `&renderer.instance` 这种指针不能跨调用保存。
    pub const Context = struct {
        shared: *const Device.Shared,
        physical_device: vk.PhysicalDevice,
        instance: *const Instance,
    };

    pub fn init(context: Context, width: u32, height: u32) !SwapChain {
        var self = SwapChain{
            .shared = context.shared,
            .physical_device = context.physical_device,
            .surface = context.instance.surface,
        };
        errdefer self.deinit();

        self.depth_format = try chooseDepthFormat(&context.instance.wrapper, context.physical_device);
        try self.rebuild(context, width, height);
        return self;
    }

    /// 重建交换链（resize 或 `VK_ERROR_OUT_OF_DATE_KHR` 后调用）。
    ///
    /// 保留 `old_swapchain` 让驱动有机会复用资源；`rebuild` 内部先等 GPU 空闲
    /// 再销毁旧对象，最后才建新的，所以中途失败也不会留下半套资源。
    pub fn recreate(self: *SwapChain, context: Context, width: u32, height: u32) !void {
        try self.rebuild(context, width, height);
    }

    fn rebuild(self: *SwapChain, context: Context, width: u32, height: u32) !void {
        const w = &self.shared.wrapper;

        // 重建前必须等 GPU 用完旧资源。
        try w.deviceWaitIdle(self.shared.device);
        self.releaseImages();

        try self.createSwapchain(context, width, height);
        try self.createViewsAndFramebuffers();
    }

    pub fn deinit(self: *SwapChain) void {
        const w = &self.shared.wrapper;

        w.deviceWaitIdle(self.shared.device) catch {};
        self.releaseImages();

        if (self.render_pass != .null) {
            w.destroyRenderPass(self.shared.device, self.render_pass, null);
            self.render_pass = .null;
        }
        self.shared = undefined;
    }

    /// 交换链图像数（`Sync.image_in_flight` 的长度）。
    pub fn imageCount(self: *const SwapChain) u32 {
        return @intCast(self.views.len);
    }

    pub fn framebuffer(self: *const SwapChain, image_index: u32) vk.Framebuffer {
        return self.framebuffers[image_index];
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn createSwapchain(self: *SwapChain, context: Context, width: u32, height: u32) !void {
        const shared = self.shared;
        const w = &shared.wrapper;
        const iw = &context.instance.wrapper;

        const capabilities = try iw.getPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface);

        const surface_format = try chooseSurfaceFormat(iw, self.physical_device, self.surface);
        self.format = surface_format.format;

        const extent = chooseExtent(capabilities, width, height);
        if (extent.width == 0 or extent.height == 0) return error.ZeroSurfaceExtent;
        self.extent = extent;

        var image_count: u32 = capabilities.min_image_count + 1;
        // max_image_count == 0 表示没有上限。
        if (capabilities.max_image_count != 0 and image_count > capabilities.max_image_count) {
            image_count = capabilities.max_image_count;
        }

        const present_mode = try choosePresentMode(iw, self.physical_device, self.surface);

        const create_info = vk.SwapchainCreateInfoKHR{
            .surface = self.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment = true },
            // graphics 与 present 队列族相同（Device 选型时保证），用 exclusive 即可。
            .image_sharing_mode = .exclusive,
            .pre_transform = capabilities.current_transform,
            .composite_alpha = chooseCompositeAlpha(capabilities.supported_composite_alpha),
            .present_mode = present_mode,
            .clipped = .true,
            .old_swapchain = self.handle,
        };

        const new_handle = try w.createSwapchainKHR(shared.device, &create_info, null);

        // 新交换链建好后才销毁旧的，失败时还能回退。
        if (self.handle != .null) w.destroySwapchainKHR(shared.device, self.handle, null);
        self.handle = new_handle;

        var count: u32 = 0;
        _ = try w.getSwapchainImagesKHR(shared.device, self.handle, &count, null);
        self.images = try std.heap.page_allocator.alloc(vk.Image, count);
        _ = try w.getSwapchainImagesKHR(shared.device, self.handle, &count, self.images.ptr);

        if (self.render_pass == .null) {
            self.render_pass = try createRenderPass(shared, self.format, self.depth_format);
        }

        std.log.info("Vulkan 交换链：{d}x{d}，{d} 张图像，present 模式 {s}", .{
            extent.width,
            extent.height,
            count,
            @tagName(present_mode),
        });
    }

    /// 深度图每张交换链图像共用一张（同尺寸，不需要 per-image）。
    fn createViewsAndFramebuffers(self: *SwapChain) !void {
        const shared = self.shared;
        const w = &shared.wrapper;
        const allocator = std.heap.page_allocator;

        self.views = try allocator.alloc(vk.ImageView, self.images.len);
        @memset(self.views, .null);
        errdefer {
            for (self.views) |view| {
                if (view != .null) w.destroyImageView(shared.device, view, null);
            }
        }

        for (self.images, 0..) |image, i| {
            self.views[i] = try w.createImageView(shared.device, &.{
                .image = image,
                .view_type = .@"2d",
                .format = self.format,
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .subresource_range = .{
                    .aspect_mask = .{ .color = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            }, null);
        }

        try self.createDepthResources();

        self.framebuffers = try allocator.alloc(vk.Framebuffer, self.images.len);
        @memset(self.framebuffers, .null);
        errdefer {
            for (self.framebuffers) |fb| {
                if (fb != .null) w.destroyFramebuffer(shared.device, fb, null);
            }
        }

        for (self.views, 0..) |color_view, i| {
            const attachments = [_]vk.ImageView{ color_view, self.depth_view };
            self.framebuffers[i] = try w.createFramebuffer(shared.device, &.{
                .render_pass = self.render_pass,
                .attachment_count = attachments.len,
                .p_attachments = &attachments,
                .width = self.extent.width,
                .height = self.extent.height,
                .layers = 1,
            }, null);
        }
    }

    fn createDepthResources(self: *SwapChain) !void {
        const shared = self.shared;
        const w = &shared.wrapper;

        const image = try w.createImage(shared.device, &.{
            .image_type = .@"2d",
            .format = self.depth_format,
            .extent = .{
                .width = self.extent.width,
                .height = self.extent.height,
                .depth = 1,
            },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1" = true },
            .tiling = .optimal,
            .usage = .{ .depth_stencil_attachment = true },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        }, null);
        errdefer w.destroyImage(shared.device, image, null);

        const requirements = w.getImageMemoryRequirements(shared.device, image);
        const memory_type = try shared.findMemoryType(requirements.memory_type_bits, .{ .device_local = true });

        const memory = try w.allocateMemory(shared.device, &.{
            .allocation_size = requirements.size,
            .memory_type_index = memory_type,
        }, null);
        errdefer w.freeMemory(shared.device, memory, null);

        try w.bindImageMemory(shared.device, image, memory, 0);

        const has_stencil = self.depth_format == .d24_unorm_s8_uint or self.depth_format == .d32_sfloat_s8_uint;
        const view = try w.createImageView(shared.device, &.{
            .image = image,
            .view_type = .@"2d",
            .format = self.depth_format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{
                    .depth = true,
                    .stencil = has_stencil,
                },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);

        self.depth_image = image;
        self.depth_memory = memory;
        self.depth_view = view;
    }

    /// 释放与交换链图像相关的一切（render pass 与 surface 不动）。
    fn releaseImages(self: *SwapChain) void {
        const shared = self.shared;
        const w = &shared.wrapper;

        for (self.framebuffers) |fb| {
            if (fb != .null) w.destroyFramebuffer(shared.device, fb, null);
        }
        for (self.views) |view| {
            if (view != .null) w.destroyImageView(shared.device, view, null);
        }

        const allocator = std.heap.page_allocator;
        if (self.framebuffers.len != 0) allocator.free(self.framebuffers);
        if (self.views.len != 0) allocator.free(self.views);
        if (self.images.len != 0) allocator.free(self.images);

        self.framebuffers = &.{};
        self.views = &.{};
        self.images = &.{};

        if (self.depth_view != .null) {
            w.destroyImageView(shared.device, self.depth_view, null);
            self.depth_view = .null;
        }
        if (self.depth_image != .null) {
            w.destroyImage(shared.device, self.depth_image, null);
            self.depth_image = .null;
        }
        if (self.depth_memory != .null) {
            w.freeMemory(shared.device, self.depth_memory, null);
            self.depth_memory = .null;
        }
    }
};

// =============================================================================
// 选择与创建
// =============================================================================

fn createRenderPass(shared: *const Device.Shared, color_format: vk.Format, depth_format: vk.Format) !vk.RenderPass {
    const attachments = [_]vk.AttachmentDescription{
        .{
            .format = color_format,
            .samples = .{ .@"1" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            // undefined → present_src：渲染 pass 自己完成布局转换。
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        },
        .{
            .format = depth_format,
            .samples = .{ .@"1" = true },
            .load_op = .clear,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .depth_stencil_attachment_optimal,
        },
    };

    // 用数组而不是单个变量：`&x` 是单指针，Zig 不会隐式转成 `[*]const T`，
    // 数组的 `&arr` 会。
    const color_refs = [_]vk.AttachmentReference{
        .{ .attachment = 0, .layout = .color_attachment_optimal },
    };
    const depth_refs = [_]vk.AttachmentReference{
        .{ .attachment = 1, .layout = .depth_stencil_attachment_optimal },
    };

    const subpasses = [_]vk.SubpassDescription{
        .{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = color_refs.len,
            .p_color_attachments = &color_refs,
            // 这个字段是单指针（可选的单个附件引用），不是 many-pointer。
            .p_depth_stencil_attachment = &depth_refs[0],
        },
    };

    // 每帧都 clear，上一帧写完直接给下一帧用，不需要外部依赖保内容。
    const dependencies = [_]vk.SubpassDependency{
        .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output = true, .early_fragment_tests = true },
            .dst_stage_mask = .{ .color_attachment_output = true, .early_fragment_tests = true },
            .src_access_mask = .{},
            .dst_access_mask = .{
                .color_attachment_write = true,
                .depth_stencil_attachment_write = true,
            },
        },
    };

    return shared.wrapper.createRenderPass(shared.device, &.{
        .attachment_count = attachments.len,
        .p_attachments = &attachments,
        .subpass_count = subpasses.len,
        .p_subpasses = &subpasses,
        .dependency_count = dependencies.len,
        .p_dependencies = &dependencies,
    }, null);
}

fn chooseSurfaceFormat(
    iw: *const vk.InstanceWrapper,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) !vk.SurfaceFormatKHR {
    var count: u32 = 0;
    _ = try iw.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, null);
    if (count == 0) return error.NoSurfaceFormats;

    const allocator = std.heap.page_allocator;
    const formats = try allocator.alloc(vk.SurfaceFormatKHR, count);
    defer allocator.free(formats);
    _ = try iw.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, formats.ptr);

    for (formats) |format| {
        // 与 D3D11 后端的 R8G8B8A8_UNORM 语义一致（不做 sRGB 编码转换）。
        if (format.format == .b8g8r8a8_unorm and format.color_space == .srgb_nonlinear_khr) return format;
        if (format.format == .r8g8b8a8_unorm and format.color_space == .srgb_nonlinear_khr) return format;
    }

    // 只有一种格式时驱动把它填成 undefined，表示「随便挑」。
    if (count == 1 and formats[0].format == .undefined) {
        return .{ .format = .b8g8r8a8_unorm, .color_space = .srgb_nonlinear_khr };
    }
    return formats[0];
}

fn choosePresentMode(
    iw: *const vk.InstanceWrapper,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) !vk.PresentModeKHR {
    var count: u32 = 0;
    _ = try iw.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, null);
    if (count == 0) return error.NoPresentModes;

    const allocator = std.heap.page_allocator;
    const modes = try allocator.alloc(vk.PresentModeKHR, count);
    defer allocator.free(modes);
    _ = try iw.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, modes.ptr);

    for (modes) |mode| {
        if (mode == preferred_present_mode) return mode;
    }
    // fifo 是规范保证支持的兜底。
    return .fifo_khr;
}

/// 交换链尺寸：`current_extent` 是窗口给的固定值；等于 UINT32_MAX 时才自己算。
fn chooseExtent(capabilities: vk.SurfaceCapabilitiesKHR, width: u32, height: u32) vk.Extent2D {
    if (capabilities.current_extent.width != std.math.maxInt(u32)) return capabilities.current_extent;

    return .{
        .width = std.math.clamp(width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
        .height = std.math.clamp(height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
    };
}

/// 选一个支持的合成 alpha；优先 opaque（不参与窗口混合）。
fn chooseCompositeAlpha(supported: vk.CompositeAlphaFlagsKHR) vk.CompositeAlphaFlagsKHR {
    if (supported.opaque_khr) return .{ .opaque_khr = true };
    if (supported.pre_multiplied_khr) return .{ .pre_multiplied_khr = true };
    if (supported.post_multiplied_khr) return .{ .post_multiplied_khr = true };
    return .{ .inherit_khr = true };
}

/// `vkGetPhysicalDeviceFormatProperties` 是 instance 层函数，所以这里拿
/// InstanceWrapper 而不是 DeviceWrapper。
fn chooseDepthFormat(iw: *const vk.InstanceWrapper, physical_device: vk.PhysicalDevice) !vk.Format {
    const candidates = [_]vk.Format{ .d32_sfloat, .d32_sfloat_s8_uint, .d24_unorm_s8_uint };

    for (candidates) |format| {
        const props = iw.getPhysicalDeviceFormatProperties(physical_device, format);
        if (props.optimal_tiling_features.depth_stencil_attachment) return format;
    }
    return error.NoDepthFormat;
}
