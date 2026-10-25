//! D3D12 设备与它周边的「每设备一份」对象：命令队列、命令分配器/命令表、
//! fence、RTV/DSV 描述符堆、DXGI 工厂。
//!
//! D3D12 没有立即上下文，所有渲染命令都要录进命令表再提交给队列；这里的
//! 命令表/分配器是单份、串行复用的（宿主每帧驱动一次，帧与帧之间用 fence
//! 同步），这也是后端内 `frames_in_flight = 2` 的常量缓冲环形布局成立的前提。

const std = @import("std");

const win32 = @import("win32").everything;

const Error = @import("Error.zig");

/// 交换链后台缓冲区数量。RTV 堆按这个数开槽。
pub const buffer_count = 2;

pub const Device = struct {
    d3d_device: *win32.ID3D12Device,
    /// 工厂必须活得比交换链久（交换链创建时引用它的队列/工厂），随 Device 持有。
    factory: *win32.IDXGIFactory2,
    command_queue: *win32.ID3D12CommandQueue,
    command_allocator: *win32.ID3D12CommandAllocator,
    command_list: *win32.ID3D12GraphicsCommandList,

    fence: *win32.ID3D12Fence,
    fence_event: win32.HANDLE,
    /// 已 Signal 的最新 fence 值；`waitForGpu` 用它判断 GPU 是否追上。
    fence_value: u64 = 0,

    rtv_heap: *win32.ID3D12DescriptorHeap,
    dsv_heap: *win32.ID3D12DescriptorHeap,
    rtv_descriptor_size: u32,

    pub fn init() !Device {
        // 没装「图形工具」可选功能时调试层起不来：警告后降级，不让引擎挂掉。
        return create(true) catch |err| {
            std.log.warn("带调试层创建 D3D12 设备失败（{s}），回退到普通模式", .{@errorName(err)});
            return create(false);
        };
    }

    fn create(debug: bool) !Device {
        if (debug) {
            enableDebugLayer() catch |err| {
                std.log.warn("启用 D3D12 调试层失败（{s}）", .{@errorName(err)});
            };
        }

        // 默认适配器（传 null）就够了；真到没有硬件适配器的机器上再考虑枚举 WARP。
        var d3d_device: ?*win32.ID3D12Device = null;
        try Error.check(
            win32.D3D12CreateDevice(null, win32.D3D_FEATURE_LEVEL_11_0, win32.IID_ID3D12Device, @ptrCast(&d3d_device)),
            "创建 D3D12 设备",
        );
        errdefer _ = d3d_device.?.IUnknown.Release();

        var factory: ?*win32.IDXGIFactory2 = null;
        try Error.check(
            win32.CreateDXGIFactory2(0, win32.IID_IDXGIFactory2, @ptrCast(&factory)),
            "创建 DXGI 工厂",
        );
        errdefer _ = factory.?.IUnknown.Release();

        const queue_desc = win32.D3D12_COMMAND_QUEUE_DESC{
            .Type = win32.D3D12_COMMAND_LIST_TYPE_DIRECT,
            .Priority = 0,
            .Flags = win32.D3D12_COMMAND_QUEUE_FLAG_NONE,
            .NodeMask = 0,
        };
        var command_queue: ?*win32.ID3D12CommandQueue = null;
        try Error.check(
            d3d_device.?.CreateCommandQueue(&queue_desc, win32.IID_ID3D12CommandQueue, @ptrCast(&command_queue)),
            "创建命令队列",
        );
        errdefer _ = command_queue.?.IUnknown.Release();

        var command_allocator: ?*win32.ID3D12CommandAllocator = null;
        try Error.check(
            d3d_device.?.CreateCommandAllocator(
                win32.D3D12_COMMAND_LIST_TYPE_DIRECT,
                win32.IID_ID3D12CommandAllocator,
                @ptrCast(&command_allocator),
            ),
            "创建命令分配器",
        );
        errdefer _ = command_allocator.?.IUnknown.Release();

        // 命令表创建出来就处于录制状态；先关掉，让每帧开头的 Reset 能成功。
        var command_list: ?*win32.ID3D12GraphicsCommandList = null;
        try Error.check(
            d3d_device.?.CreateCommandList(
                0,
                win32.D3D12_COMMAND_LIST_TYPE_DIRECT,
                command_allocator.?,
                null,
                win32.IID_ID3D12GraphicsCommandList,
                @ptrCast(&command_list),
            ),
            "创建命令表",
        );
        errdefer _ = command_list.?.IUnknown.Release();
        try Error.check(command_list.?.Close(), "关闭初始命令表");

        var fence: ?*win32.ID3D12Fence = null;
        try Error.check(
            d3d_device.?.CreateFence(0, win32.D3D12_FENCE_FLAG_NONE, win32.IID_ID3D12Fence, @ptrCast(&fence)),
            "创建 fence",
        );
        errdefer _ = fence.?.IUnknown.Release();

        const fence_event = win32.CreateEventW(null, 0, 0, null) orelse
            return error.EventCreationFailed;
        errdefer _ = win32.CloseHandle(fence_event);

        // RTV/DSV 都是 CPU 侧的，不用 SHADER_VISIBLE；常量走根描述符（直接 GPU 虚拟
        // 地址），连 CBV 堆都不需要。
        const rtv_heap = try createDescriptorHeap(d3d_device.?, .RTV, buffer_count);
        errdefer _ = rtv_heap.IUnknown.Release();
        const dsv_heap = try createDescriptorHeap(d3d_device.?, .DSV, 4);
        errdefer _ = dsv_heap.IUnknown.Release();

        return Device{
            .d3d_device = d3d_device.?,
            .factory = factory.?,
            .command_queue = command_queue.?,
            .command_allocator = command_allocator.?,
            .command_list = command_list.?,
            .fence = fence.?,
            .fence_event = fence_event,
            .rtv_heap = rtv_heap,
            .dsv_heap = dsv_heap,
            .rtv_descriptor_size = d3d_device.?.GetDescriptorHandleIncrementSize(.RTV),
        };
    }

    pub fn deinit(self: *Device) void {
        self.waitForGpu();
        _ = win32.CloseHandle(self.fence_event);
        _ = self.dsv_heap.IUnknown.Release();
        _ = self.rtv_heap.IUnknown.Release();
        _ = self.fence.IUnknown.Release();
        _ = self.command_list.IUnknown.Release();
        _ = self.command_allocator.IUnknown.Release();
        _ = self.command_queue.IUnknown.Release();
        _ = self.factory.IUnknown.Release();
        _ = self.d3d_device.IUnknown.Release();
    }

    /// 等 GPU 把已提交的命令全部执行完。
    ///
    /// 每帧开头调一次：保证上一帧（包括 ResizeBuffers 前的资源释放）都已落地，
    /// 代价是 CPU/GPU 不重叠——对这个规模的引擎是「先对后快」的取舍。
    pub fn waitForGpu(self: *Device) void {
        self.fence_value += 1;
        Error.check(self.command_queue.Signal(self.fence, self.fence_value), "fence Signal") catch return;
        if (self.fence.GetCompletedValue() < self.fence_value) {
            Error.check(
                self.fence.SetEventOnCompletion(self.fence_value, self.fence_event),
                "fence SetEventOnCompletion",
            ) catch return;
            _ = win32.WaitForSingleObject(self.fence_event, win32.INFINITE);
        }
    }

    /// 第 `index` 个 RTV 槽位的 CPU 句柄。
    pub fn rtvHandle(self: *const Device, index: u32) win32.D3D12_CPU_DESCRIPTOR_HANDLE {
        var handle = self.rtv_heap.GetCPUDescriptorHandleForHeapStart();
        handle.ptr += @as(usize, self.rtv_descriptor_size) * index;
        return handle;
    }

    fn enableDebugLayer() !void {
        var debug: ?*win32.ID3D12Debug = null;
        try Error.check(
            win32.D3D12GetDebugInterface(win32.IID_ID3D12Debug, @ptrCast(&debug)),
            "获取 ID3D12Debug",
        );
        defer _ = debug.?.IUnknown.Release();
        debug.?.EnableDebugLayer();
    }

    fn createDescriptorHeap(
        device: *win32.ID3D12Device,
        heap_type: win32.D3D12_DESCRIPTOR_HEAP_TYPE,
        count: u32,
    ) !*win32.ID3D12DescriptorHeap {
        const desc = win32.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = heap_type,
            .NumDescriptors = count,
            .Flags = win32.D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
            .NodeMask = 0,
        };
        var heap: ?*win32.ID3D12DescriptorHeap = null;
        try Error.check(
            device.CreateDescriptorHeap(&desc, win32.IID_ID3D12DescriptorHeap, @ptrCast(&heap)),
            "创建描述符堆",
        );
        return heap.?;
    }
};
