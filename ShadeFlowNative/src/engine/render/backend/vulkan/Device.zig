//! VkPhysicalDevice 选择 + VkDevice / 队列 / 显存分配。
//!
//! 选择规则：必须同时具备 graphics 队列族和支持 present 的队列族，并且
//! 设备扩展里有 `VK_KHR_swapchain`；同等条件下优先独显。
//!
//! `shared` 是堆上的稳定副本。`Renderer` 会按值返回/移动（`Engine.renderer`
//! 持有值），而 `Buffer` / `Shader` 的生命周期远长于某一次 Renderer 搬家，
//! 所以它们持有的不是 `*Device` 而是 `*const Device.Shared`：handle 与函数
//! 指针表都待在不会随 Renderer 移动的内存里。

const std = @import("std");

const vk = @import("vulkan");

const Instance = @import("Instance.zig").Instance;

const Candidate = struct {
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    graphics_family: u32,
    present_family: u32,
};

pub const Device = struct {
    shared: *Shared,
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,

    /// 跨 `Buffer` / `Shader` 共享的设备侧句柄与函数指针表。
    ///
    /// 只在 `Device.deinit` 里释放；持有方不得在那之后访问。
    pub const Shared = struct {
        device: vk.Device,
        wrapper: vk.DeviceWrapper,
        memory: vk.PhysicalDeviceMemoryProperties,

        graphics_family: u32,
        present_family: u32,
        graphics_queue: vk.Queue,
        present_queue: vk.Queue,

        /// `fillModeNonSolid`：线框模式（`Types.FillMode.wireframe`）的前提。
        supports_wireframe: bool,

        /// 资源上传用的一次性命令池（`VK_COMMAND_POOL_CREATE_TRANSIENT_BIT`）。
        transient_pool: vk.CommandPool,

        /// `type_bits` 是资源的 `MemoryRequirements.memory_type_bits`（驱动给的
        /// 允许集合），`required` 是期望的属性；两者必须同时满足。
        pub fn findMemoryType(
            self: *const Shared,
            type_bits: u32,
            required: vk.MemoryPropertyFlags,
        ) !u32 {
            const required_bits: u32 = @bitCast(required);
            for (0..self.memory.memory_type_count) |index| {
                const bit = @as(u32, 1) << @intCast(index);
                if (type_bits & bit == 0) continue;

                const candidate: u32 = @bitCast(self.memory.memory_types[index].property_flags);
                if ((candidate & required_bits) == required_bits) return @intCast(index);
            }
            return error.NoSuitableMemoryType;
        }
    };

    pub fn init(instance: *const Instance) !Device {
        const allocator = std.heap.page_allocator;

        const physical_devices = try instance.wrapper.enumeratePhysicalDevicesAlloc(instance.handle, allocator);
        defer allocator.free(physical_devices);
        if (physical_devices.len == 0) return error.NoVulkanDevice;

        var fallback: ?Candidate = null;
        var chosen: ?Candidate = null;

        for (physical_devices) |physical_device| {
            const properties = instance.wrapper.getPhysicalDeviceProperties(physical_device);

            const families = instance.wrapper.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, allocator) catch continue;
            defer allocator.free(families);

            var graphics: ?u32 = null;
            var present: ?u32 = null;
            for (families, 0..) |family, index| {
                const family_index: u32 = @intCast(index);
                if (graphics == null and family.queue_flags.graphics) {
                    graphics = family_index;
                }
                if (present == null) {
                    const supported = instance.wrapper.getPhysicalDeviceSurfaceSupportKHR(
                        physical_device,
                        family_index,
                        instance.surface,
                    ) catch vk.Bool32.false;
                    if (supported == .true) present = family_index;
                }
            }

            const graphics_family = graphics orelse continue;
            const present_family = present orelse continue;

            if (!try hasDeviceExtension(instance, physical_device, vk.device_extensions.khr_swapchain.name, allocator)) continue;

            const candidate = Candidate{
                .physical_device = physical_device,
                .properties = properties,
                .graphics_family = graphics_family,
                .present_family = present_family,
            };

            if (fallback == null) fallback = candidate;
            if (properties.device_type == .discrete_gpu) {
                chosen = candidate;
                break;
            }
        }

        const selected = chosen orelse fallback orelse return error.NoSuitableVulkanDevice;

        var priorities = [_]f32{1.0};
        var queue_infos: [2]vk.DeviceQueueCreateInfo = undefined;
        queue_infos[0] = .{
            .queue_family_index = selected.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priorities,
        };
        var queue_info_count: u32 = 1;
        if (selected.present_family != selected.graphics_family) {
            queue_infos[1] = .{
                .queue_family_index = selected.present_family,
                .queue_count = 1,
                .p_queue_priorities = &priorities,
            };
            queue_info_count = 2;
        }

        const extension_names = [_][*:0]const u8{vk.device_extensions.khr_swapchain.name.ptr};

        // 线框模式（Types.FillMode.wireframe）要这个特性；设备不支持就退回实心。
        const features = instance.wrapper.getPhysicalDeviceFeatures(selected.physical_device);
        const want_fill_mode_non_solid = features.fill_mode_non_solid == .true;
        const enabled_features = vk.PhysicalDeviceFeatures{
            .fill_mode_non_solid = if (want_fill_mode_non_solid) .true else .false,
        };

        const create_info = vk.DeviceCreateInfo{
            .queue_create_info_count = queue_info_count,
            .p_queue_create_infos = &queue_infos,
            .enabled_extension_count = 1,
            .pp_enabled_extension_names = &extension_names,
            .p_enabled_features = &enabled_features,
        };

        const device = try instance.wrapper.createDevice(selected.physical_device, &create_info, null);

        const wrapper = vk.DeviceWrapper.load(device, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

        const shared = allocator.create(Shared) catch {
            wrapper.destroyDevice(device, null);
            return error.OutOfMemory;
        };
        errdefer allocator.destroy(shared);

        const transient_pool = wrapper.createCommandPool(device, &.{
            .flags = .{ .transient = true },
            .queue_family_index = selected.graphics_family,
        }, null) catch |err| {
            wrapper.destroyDevice(device, null);
            return err;
        };

        shared.* = .{
            .device = device,
            .wrapper = wrapper,
            .memory = instance.wrapper.getPhysicalDeviceMemoryProperties(selected.physical_device),
            .graphics_family = selected.graphics_family,
            .present_family = selected.present_family,
            .graphics_queue = wrapper.getDeviceQueue(device, selected.graphics_family, 0),
            .present_queue = wrapper.getDeviceQueue(device, selected.present_family, 0),
            .transient_pool = transient_pool,
            .supports_wireframe = want_fill_mode_non_solid,
        };

        std.log.info("Vulkan 设备: {s}（graphics 队列族 {d}，present 队列族 {d}）", .{
            std.mem.sliceTo(&selected.properties.device_name, 0),
            selected.graphics_family,
            selected.present_family,
        });

        return .{
            .shared = shared,
            .physical_device = selected.physical_device,
            .properties = selected.properties,
        };
    }

    pub fn deinit(self: *Device) void {
        const shared = self.shared;
        const w = &shared.wrapper;

        w.deviceWaitIdle(shared.device) catch {};
        w.destroyCommandPool(shared.device, shared.transient_pool, null);
        w.destroyDevice(shared.device, null);
        std.heap.page_allocator.destroy(shared);
        self.shared = undefined;
    }

    pub fn minUniformBufferOffsetAlignment(self: *const Device) vk.DeviceSize {
        const alignment = self.properties.limits.min_uniform_buffer_offset_alignment;
        return if (alignment == 0) 1 else alignment;
    }

    fn hasDeviceExtension(
        instance: *const Instance,
        physical_device: vk.PhysicalDevice,
        name: []const u8,
        allocator: std.mem.Allocator,
    ) !bool {
        const properties = instance.wrapper.enumerateDeviceExtensionPropertiesAlloc(
            physical_device,
            null,
            allocator,
        ) catch |err| {
            std.log.warn("枚举设备扩展失败: {s}", .{@errorName(err)});
            return false;
        };
        defer allocator.free(properties);

        for (properties) |property| {
            if (std.mem.eql(u8, std.mem.sliceTo(&property.extension_name, 0), name)) return true;
        }
        return false;
    }
};
