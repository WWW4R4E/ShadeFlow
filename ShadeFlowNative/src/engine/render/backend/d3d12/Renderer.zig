//! D3D12 渲染后端。
//!
//! 对外契约（与 `Types.zig` 一起）由 `render/Renderer.zig` 转出；`Engine` 只
//! 通过那层门面使用它。
//!
//! 契约以严格后端为基线：管线状态在 `createPipeline` 时烘进 PSO，draw 时
//! 只做绑定 + 录制，没有「随时改状态」。
//!
//! 帧同步差异备忘（与 Vulkan 后端不对齐，待优化）：D3D12 目前每帧
//! `beginFrame` 里 `waitForGpu`——1 帧 in-flight、「先对后快」；Vulkan 是
//! 2 帧 in-flight（per-frame fence/semaphore/命令缓冲）。后续优化方向是把
//! 命令分配器 / 常量环 / fence 扩成双缓冲，去掉 beginFrame 的等待。
//!
//! 常量缓冲：单个 Constants 224B 按 256B 一槽（D3D12 要求 256 对齐），
//! `buffer_count` 个槽的环形布局，draw 时写当前帧的槽——beginFrame 的
//! fence 等待保证槽不会被上一帧踩。

const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Error = @import("Error.zig");

const BufferImpl = @import("Buffer.zig").Buffer;
const BufferAlignment = @import("Buffer.zig").constant_buffer_alignment;
const Device = @import("Device.zig").Device;
const buffer_count = @import("Device.zig").buffer_count;
const PipelineImpl = @import("Pipeline.zig").Pipeline;
const ShaderImpl = @import("Shader.zig").Shader;
const SwapChain = @import("SwapChain.zig").SwapChain;
const TextureImpl = @import("Texture.zig").Texture;

pub const Renderer = struct {
    // 供门面/场景层使用的资源类型（不含任何方法约定上的后端差异）。
    pub const Buffer = BufferImpl;
    pub const Shader = ShaderImpl;
    pub const Texture = TextureImpl;
    pub const Pipeline = PipelineImpl;

    device: Device,
    swap_chain: SwapChain,

    back_buffers: [buffer_count]?*win32.ID3D12Resource = @splat(null),
    depth_texture: Texture,

    width: u32,
    height: u32,

    /// 常量缓冲区在第一次 draw 按数据大小懒创建（256 对齐 × 槽数）。
    constant_buffer: ?Buffer = null,
    /// 1×1 白色默认纹理：不贴图的对象绑它（懒创建，渲染器生命周期持有）。
    default_texture: ?Texture = null,

    // =========================================================================
    // 初始化
    // =========================================================================

    /// WinUI 3 Composition 模式（由 C# 驱动，DLL 导出）。
    pub fn initForComposition(width: u32, height: u32) !Renderer {
        var device = try Device.init();
        errdefer device.deinit();

        var swap_chain = try SwapChain.initForComposition(&device, width, height);
        errdefer swap_chain.deinit();

        var self = Renderer{
            .device = device,
            .swap_chain = swap_chain,
            .depth_texture = Texture.init(.depth_stencil),
            .width = width,
            .height = height,
        };

        // 失败时由上面的 errdefer 释放 device/swap_chain；这里不要用
        // errdefer self.deinit()，否则会和那两条一起重复 Release。
        try self.createPipelineResources(width, height);
        return self;
    }

    /// 独立窗口模式（原生句柄来自 `host/native_handles.zig`）。
    pub fn initForHwnd(native: Types.NativeWindow, width: u32, height: u32) !Renderer {
        const hwnd: win32.HWND = switch (native) {
            .win32 => |handles| @ptrCast(@alignCast(handles.hwnd)),
            else => return error.UnsupportedNativeWindow,
        };

        var device = try Device.init();
        errdefer device.deinit();

        var swap_chain = try SwapChain.initForHwnd(&device, hwnd, width, height);
        errdefer swap_chain.deinit();

        var self = Renderer{
            .device = device,
            .swap_chain = swap_chain,
            .depth_texture = Texture.init(.depth_stencil),
            .width = width,
            .height = height,
        };

        try self.createPipelineResources(width, height);
        return self;
    }

    pub fn deinit(self: *Renderer) void {
        // deinit 可能发生在帧中间（命令表还在录制态），Close 让它回到可提交
        // 状态，Device.deinit 里的 waitForGpu 才不会碰上非法状态。
        _ = self.device.command_list.Close();

        if (self.default_texture) |*t| t.deinit();
        if (self.constant_buffer) |*cb| cb.deinit();
        self.releasePipelineResources();
        self.depth_texture.deinit();
        self.swap_chain.deinit();
        self.device.deinit();
    }

    // =========================================================================
    // 帧
    // =========================================================================

    pub fn beginFrame(self: *Renderer, clear_color: Types.ClearColor) void {
        const device = &self.device;
        const list = device.command_list;

        // 上一帧（含它引用的所有上传堆内存）必须已执行完，才能 Reset 分配器、
        // 覆写常量缓冲槽。（Vulkan 后端是 2 帧 in-flight，这里是本后端的
        // 「先对后快」取舍，见文件头备忘。）
        device.waitForGpu();
        Error.check(device.command_allocator.Reset(), "重置命令分配器") catch return;
        Error.check(
            list.Reset(device.command_allocator, null),
            "重置命令表",
        ) catch return;

        const index = self.swap_chain.currentBackBufferIndex();
        const back_buffer = self.back_buffers[index] orelse return;

        // COMMON（= PRESENT）→ RENDER_TARGET。上一帧结束时已转回。
        const to_rt = transitionBarrier(back_buffer, win32.D3D12_RESOURCE_STATE_COMMON, win32.D3D12_RESOURCE_STATE_RENDER_TARGET);
        list.ResourceBarrier(1, @ptrCast(&to_rt));

        var dsv = self.depth_texture.getDepthStencilView();
        if (dsv) |handle| {
            list.ClearDepthStencilView(
                handle,
                .{ .DEPTH = 1 },
                1.0,
                0,
                0,
                @ptrCast(&[_]win32.RECT{}),
            );
        }

        const rtv = device.rtvHandle(index);
        const color: Types.ClearColor = clear_color;
        list.ClearRenderTargetView(rtv, &color[0], 0, @ptrCast(&[_]win32.RECT{}));
        list.OMSetRenderTargets(1, &rtv, 0, if (dsv != null) &dsv.? else null);

        const viewport = win32.D3D12_VIEWPORT{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(self.width),
            .Height = @floatFromInt(self.height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };
        list.RSSetViewports(1, @ptrCast(&viewport));

        const scissor = win32.RECT{
            .left = 0,
            .top = 0,
            .right = @intCast(self.width),
            .bottom = @intCast(self.height),
        };
        list.RSSetScissorRects(1, @ptrCast(&scissor));
    }

    pub fn endFrame(self: *Renderer) void {
        const device = &self.device;
        const list = device.command_list;

        const index = self.swap_chain.currentBackBufferIndex();
        if (self.back_buffers[index]) |back_buffer| {
            const to_present = transitionBarrier(back_buffer, win32.D3D12_RESOURCE_STATE_RENDER_TARGET, win32.D3D12_RESOURCE_STATE_COMMON);
            list.ResourceBarrier(1, @ptrCast(&to_present));
        }

        Error.check(list.Close(), "关闭命令表") catch return;
        var lists = [_]?*win32.ID3D12CommandList{@ptrCast(list)};
        device.command_queue.ExecuteCommandLists(lists.len, &lists);

        self.swap_chain.present();
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) !void {
        // ResizeBuffers 要求：GPU 空闲 + 无人持有后台缓冲区引用。
        self.device.waitForGpu();
        self.releasePipelineResources();

        try self.swap_chain.resizeBuffers(width, height);
        try self.createPipelineResources(width, height);

        self.width = width;
        self.height = height;
    }

    /// WinUI 侧 `ISwapChainPanelNative::SetSwapChain` 用的裸指针。
    pub fn swapChainInteropHandle(self: *Renderer) ?*anyopaque {
        return @ptrCast(self.swap_chain.handle);
    }

    // =========================================================================
    // 资源工厂
    // =========================================================================

    /// 静态顶点缓冲（上传堆一次性写入，创建后只读）。
    pub fn createVertexBuffer(
        self: *Renderer,
        data: []const u8,
        stride: u32,
    ) !Buffer {
        var buffer = Buffer.init(.vertex);
        errdefer buffer.deinit();
        try buffer.createVertexBuffer(&self.device, data, stride);
        return buffer;
    }

    pub fn createIndexBuffer(self: *Renderer, indices: []const u32) !Buffer {
        var buffer = Buffer.init(.index);
        errdefer buffer.deinit();
        try buffer.createIndexBuffer(&self.device, indices);
        return buffer;
    }

    pub fn createShaderFromFiles(
        self: *Renderer,
        vertex_path: []const u8,
        pixel_path: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        return Shader.loadProgram(&self.device, vertex_path, pixel_path, layout);
    }

    /// 从 RGBA8 像素创建颜色纹理（无 mip，加载期一次性上传）。
    pub fn createTexture(
        self: *Renderer,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) !Texture {
        return TextureImpl.createRgba8(&self.device, pixels, width, height);
    }

    /// 创建管线：着色器 × 状态一次性烘进 PSO。
    ///
    /// `shader` 由调用方持有并保证活得比返回的 Pipeline 久。
    pub fn createPipeline(
        self: *Renderer,
        shader: *const Shader,
        state: Types.PipelineState,
    ) !Pipeline {
        return Pipeline.create(&self.device, shader, state);
    }

    // =========================================================================
    // 绘制
    // =========================================================================

    pub fn draw(
        self: *Renderer,
        pipeline: *const Pipeline,
        vertex_buffer: *const Buffer,
        vertex_count: u32,
        constants: []const u8,
        texture: ?*const Texture,
    ) void {
        const list = self.device.command_list;

        self.bindDrawState(list, pipeline, constants, texture);

        const vbv = win32.D3D12_VERTEX_BUFFER_VIEW{
            .BufferLocation = vertex_buffer.gpuVirtualAddress(),
            .SizeInBytes = vertex_buffer.size,
            .StrideInBytes = vertex_buffer.stride,
        };
        list.IASetVertexBuffers(0, 1, @ptrCast(&vbv));
        list.IASetPrimitiveTopology(mapTopology(pipeline.state.topology));
        list.DrawInstanced(vertex_count, 1, 0, 0);
    }

    pub fn drawIndexed(
        self: *Renderer,
        pipeline: *const Pipeline,
        vertex_buffer: *const Buffer,
        index_buffer: *const Buffer,
        index_count: u32,
        constants: []const u8,
        texture: ?*const Texture,
    ) void {
        const list = self.device.command_list;

        self.bindDrawState(list, pipeline, constants, texture);

        const vbv = win32.D3D12_VERTEX_BUFFER_VIEW{
            .BufferLocation = vertex_buffer.gpuVirtualAddress(),
            .SizeInBytes = vertex_buffer.size,
            .StrideInBytes = vertex_buffer.stride,
        };
        list.IASetVertexBuffers(0, 1, @ptrCast(&vbv));

        const ibv = win32.D3D12_INDEX_BUFFER_VIEW{
            .BufferLocation = index_buffer.gpuVirtualAddress(),
            .SizeInBytes = index_buffer.size,
            .Format = win32.DXGI_FORMAT_R32_UINT,
        };
        list.IASetIndexBuffer(&ibv);
        list.IASetPrimitiveTopology(mapTopology(pipeline.state.topology));
        list.DrawIndexedInstanced(index_count, 1, 0, 0, 0);
    }

    // =========================================================================
    // 内部
    // =========================================================================

    /// 每次 draw 都要绑的公共状态：根签名 + 当前帧常量槽 + PSO +（带纹理
    /// 管线）描述符堆与 SRV/采样器表。
    fn bindDrawState(
        self: *Renderer,
        list: *win32.ID3D12GraphicsCommandList,
        pipeline: *const Pipeline,
        constants: []const u8,
        texture: ?*const Texture,
    ) void {
        list.SetGraphicsRootSignature(pipeline.shader.root_signature);
        list.SetPipelineState(pipeline.pso);

        if (pipeline.shader.is_textured) {
            const tex = texture orelse self.ensureDefaultTexture();
            var heaps = [_]?*win32.ID3D12DescriptorHeap{ self.device.srv_heap, self.device.sampler_heap };
            list.SetDescriptorHeaps(heaps.len, &heaps);
            list.SetGraphicsRootDescriptorTable(1, self.device.srvGpuHandle(tex.srv_slot));
            list.SetGraphicsRootDescriptorTable(2, self.device.samplerGpuHandle(tex.sampler_slot));
        }

        if (constants.len == 0) return;
        self.ensureConstantBuffer(constants.len) catch |err| {
            std.log.err("创建常量缓冲区失败: {s}", .{@errorName(err)});
            return;
        };
        const cb = &self.constant_buffer.?;
        const offset = BufferAlignment * self.swap_chain.currentBackBufferIndex();
        cb.updateConstantBuffer(constants, offset);
        list.SetGraphicsRootConstantBufferView(0, cb.gpuVirtualAddress() + offset);
    }

    /// 首次用到时创建 1×1 白色默认纹理（采样乘回去等于无纹理）。
    fn ensureDefaultTexture(self: *Renderer) *const Texture {
        if (self.default_texture == null) {
            const white = [_]u8{ 255, 255, 255, 255 };
            self.default_texture = TextureImpl.createRgba8(&self.device, &white, 1, 1) catch |err| {
                std.log.err("创建默认白纹理失败: {s}", .{@errorName(err)});
                unreachable; // 没有纹理就无法继续绘制；比画错更诚实。
            };
        }
        return &self.default_texture.?;
    }

    /// 首次 draw 按数据大小建环形常量缓冲（256 对齐 × 后台缓冲数）。
    fn ensureConstantBuffer(self: *Renderer, data_len: usize) !void {
        if (self.constant_buffer != null) return;

        const slot: u32 = @intCast(std.mem.alignForward(usize, data_len, BufferAlignment));
        var cb = Buffer.init(.constant);
        errdefer cb.deinit();
        try cb.createConstantBuffer(&self.device, slot * buffer_count);
        self.constant_buffer = cb;
    }

    fn createPipelineResources(self: *Renderer, width: u32, height: u32) !void {
        // 先建新的，全部成功后再替换（失败时保持原状）。
        var back_buffers: [buffer_count]?*win32.ID3D12Resource = @splat(null);
        for (0..buffer_count) |i| {
            back_buffers[i] = try self.swap_chain.getBackBuffer(@intCast(i));
            self.device.d3d_device.CreateRenderTargetView(
                back_buffers[i],
                null,
                self.device.rtvHandle(@intCast(i)),
            );
        }
        errdefer for (back_buffers) |bb| {
            if (bb) |b| _ = b.IUnknown.Release();
        };

        var depth = Texture.init(.depth_stencil);
        errdefer depth.deinit();
        try depth.createDepthStencil(&self.device, width, height);

        self.releasePipelineResources();
        self.back_buffers = back_buffers;
        self.depth_texture = depth;
    }

    fn releasePipelineResources(self: *Renderer) void {
        for (self.back_buffers) |bb| {
            if (bb) |b| _ = b.IUnknown.Release();
        }
        self.back_buffers = @splat(null);
        self.depth_texture.deinit();
    }
};

// =============================================================================
// 枚举映射
// =============================================================================

fn transitionBarrier(
    resource: *win32.ID3D12Resource,
    before: win32.D3D12_RESOURCE_STATES,
    after: win32.D3D12_RESOURCE_STATES,
) win32.D3D12_RESOURCE_BARRIER {
    return .{
        .Type = .TRANSITION,
        .Flags = win32.D3D12_RESOURCE_BARRIER_FLAG_NONE,
        .Anonymous = .{ .Transition = .{
            .pResource = resource,
            .Subresource = win32.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = before,
            .StateAfter = after,
        } },
    };
}

fn mapTopology(topology: Types.Topology) win32.D3D_PRIMITIVE_TOPOLOGY {
    return switch (topology) {
        .triangle_list => win32.D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST,
        .line_list => win32.D3D_PRIMITIVE_TOPOLOGY_LINELIST,
        .point_list => win32.D3D_PRIMITIVE_TOPOLOGY_POINTLIST,
    };
}
