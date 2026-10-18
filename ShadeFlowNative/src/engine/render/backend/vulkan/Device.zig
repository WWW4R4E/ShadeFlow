//! VkPhysicalDevice 选择 + VkDevice / 队列。
//!
//! 选择规则：必须同时具备 graphics 队列族和支持 present 的队列族，并且
//! 设备扩展里有 `VK_KHR_swapchain`；同等条件下优先独显。

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
    wrapper: vk.DeviceWrapper,
    handle: vk.Device,
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    graphics_family: u32,
    present_family: u32,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,

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
                if (graphics == null and family.queue_flags.graphics_bit) {
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

            if (!try hasDeviceExtension(instance, physical_device, vk.ApiInfo.khr_swapchain.name, allocator)) continue;

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

        const extension_names = [_][*:0]const u8{vk.ApiInfo.khr_swapchain.name.ptr};
        const create_info = vk.DeviceCreateInfo{
            .queue_create_info_count = queue_info_count,
            .p_queue_create_infos = &queue_infos,
            .enabled_extension_count = 1,
            .pp_enabled_extension_names = &extension_names,
        };

        const handle = try instance.wrapper.createDevice(selected.physical_device, &create_info, null);
        errdefer instance.wrapper.destroyDevice(handle, null);

        const wrapper = vk.DeviceWrapper.load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

        std.log.info("Vulkan 设备: {s}（graphics 队列族 {d}，present 队列族 {d}）", .{
            std.mem.sliceTo(&selected.properties.device_name, 0),
            selected.graphics_family,
            selected.present_family,
        });

        return .{
            .wrapper = wrapper,
            .handle = handle,
            .physical_device = selected.physical_device,
            .properties = selected.properties,
            .graphics_family = selected.graphics_family,
            .present_family = selected.present_family,
            .graphics_queue = wrapper.getDeviceQueue(handle, selected.graphics_family, 0),
            .present_queue = wrapper.getDeviceQueue(handle, selected.present_family, 0),
        };
    }

    pub fn deinit(self: *Device) void {
        self.wrapper.destroyDevice(self.handle, null);
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
