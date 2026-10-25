//! D3D12 渲染后端。
//!
//! 对外契约（与 `Types.zig` 一起）由 `render/Renderer.zig` 转出；`Engine` 只
//! 通过那层门面使用它。
//!
//! 与 D3D11 的核心区别（AGENTS.md 的备忘在这里落地）：
//! - 没有「设置状态」这种事：光栅化/深度/混合全部烘进 PSO。Renderer 保存
//!   当前状态，draw 时按「着色器 × 状态组合」查 PSO 缓存，缺了才建。
//! - 常量缓冲 256 字节对齐：单个 Constants 224B 按 256B 一槽，开
//!   `buffer_count` 个槽的环形布局，每帧写自己的槽（beginFrame 已用 fence
//!   保证上一帧 GPU 执行完，槽不会被踩）。
//! - D3D11 的 D3D11_COMPARISON/D3D11_BLEND 系列枚举在 D3D12 里换了前缀，
//!   名字一一对应。

const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Error = @import("Error.zig");

const BufferImpl = @import("Buffer.zig").Buffer;
const Device = @import("Device.zig").Device;
const buffer_count = @import("Device.zig").buffer_count;
const BufferAlignment = @import("Buffer.zig").constant_buffer_alignment;
const ShaderImpl = @import("Shader.zig").Shader;
const SwapChain = @import("SwapChain.zig").SwapChain;
const TextureImpl = @import("Texture.zig").Texture;

/// PSO 缓存键：着色器 id + 全部影响 PSO 的状态。拓扑也算了进去，因为 D3D12
/// 的 PSO 烘焙 PrimitiveTopologyType（IASetPrimitiveTopology 只能细化成同类型的
/// 具体拓扑）。
const PsoKey = struct {
    shader_id: u64,
    raster: Types.RasterState,
    depth: Types.DepthState,
    blend: Types.BlendMode,
    topology: Types.Topology,
};

pub const Renderer = struct {
    // 供门面/场景层使用的资源类型（不含任何方法约定上的后端差异）。
    pub const Buffer = BufferImpl;
    pub const Shader = ShaderImpl;
    pub const Texture = TextureImpl;

    device: Device,
    swap_chain: SwapChain,

    back_buffers: [buffer_count]?*win32.ID3D12Resource = @splat(null),
    depth_texture: Texture,

    width: u32,
    height: u32,

    /// 常量缓冲区按第一次 `setConstants` 的大小懒创建（256 对齐 × 槽数）。
    constant_buffer: ?Buffer = null,

    // 当前管线状态。D3D11 是立即上下文直接设；D3D12 只存起来，draw 时组装
    // PsoKey 查 PSO 缓存。
    raster_state: Types.RasterState = .{ .fill = .solid, .cull = .back },
    depth_state: Types.DepthState = .{},
    blend_mode: Types.BlendMode = .none,
    topology: Types.Topology = .triangle_list,

    pso_cache: std.AutoHashMapUnmanaged(PsoKey, *win32.ID3D12PipelineState) = .{},

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

        var it = self.pso_cache.iterator();
        while (it.next()) |entry| {
            _ = entry.value_ptr.*.IUnknown.Release();
        }
        self.pso_cache.deinit(std.heap.page_allocator);

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
        // 覆写常量缓冲槽。
        device.waitForGpu();
        Error.check(device.command_allocator.Reset(), "重置命令分配器") catch return;
        Error.check(
            list.Reset(device.command_allocator, null),
            "重置命令表",
        ) catch return;

        const index = self.swap_chain.currentBackBufferIndex();
        const back_buffer = self.back_buffers[index] orelse return;

        // PRESENT → RENDER_TARGET。上一帧结束时已转回 PRESENT（= COMMON）。
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

    pub fn createVertexBuffer(
        self: *Renderer,
        data: []const u8,
        stride: u32,
        usage: Types.BufferUsage,
    ) !Buffer {
        var buffer = Buffer.init(.vertex);
        errdefer buffer.deinit();
        try buffer.createVertexBuffer(&self.device, data, stride, usage);
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

    /// 每帧更新常量数据；缓冲区在首次调用时按数据大小创建（256 对齐 × 槽数）。
    pub fn setConstants(self: *Renderer, data: []const u8) !void {
        if (self.constant_buffer == null) {
            const slot: u32 = @intCast(std.mem.alignForward(usize, data.len, BufferAlignment));
            var cb = Buffer.init(.constant);
            errdefer cb.deinit();
            try cb.createConstantBuffer(&self.device, slot * buffer_count);
            self.constant_buffer = cb;
        }

        if (self.constant_buffer) |*cb| {
            const offset = BufferAlignment * self.swap_chain.currentBackBufferIndex();
            cb.updateConstantBuffer(data, offset);
        }
    }

    // =========================================================================
    // 状态（只记录，draw 时进 PSO 键）
    // =========================================================================

    pub fn setTopology(self: *Renderer, topology: Types.Topology) void {
        self.topology = topology;
    }

    pub fn setRasterState(self: *Renderer, state: Types.RasterState) !void {
        self.raster_state = state;
    }

    pub fn setBlendMode(self: *Renderer, mode: Types.BlendMode) !void {
        self.blend_mode = mode;
    }

    pub fn setDepthState(self: *Renderer, state: Types.DepthState) !void {
        self.depth_state = state;
    }

    // =========================================================================
    // 绘制
    // =========================================================================

    pub fn draw(self: *Renderer, shader: *const Shader, vertex_buffer: *const Buffer, vertex_count: u32) void {
        const pso = self.currentPso(shader) orelse return;
        const list = self.device.command_list;

        self.bindShaderCommon(list, shader, pso);

        const vbv = win32.D3D12_VERTEX_BUFFER_VIEW{
            .BufferLocation = vertex_buffer.gpuVirtualAddress(),
            .SizeInBytes = vertex_buffer.size,
            .StrideInBytes = vertex_buffer.stride,
        };
        list.IASetVertexBuffers(0, 1, @ptrCast(&vbv));
        list.IASetPrimitiveTopology(mapTopology(self.topology));
        list.DrawInstanced(vertex_count, 1, 0, 0);
    }

    pub fn drawIndexed(
        self: *Renderer,
        shader: *const Shader,
        vertex_buffer: *const Buffer,
        index_buffer: *const Buffer,
        index_count: u32,
    ) void {
        const pso = self.currentPso(shader) orelse return;
        const list = self.device.command_list;

        self.bindShaderCommon(list, shader, pso);

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
        list.IASetPrimitiveTopology(mapTopology(self.topology));
        list.DrawIndexedInstanced(index_count, 1, 0, 0, 0);
    }

    // =========================================================================
    // 内部
    // =========================================================================

    /// 每次 draw 都要绑的公共状态：根签名 + 当前帧的常量缓冲槽 + PSO。
    fn bindShaderCommon(
        self: *Renderer,
        list: *win32.ID3D12GraphicsCommandList,
        shader: *const Shader,
        pso: *win32.ID3D12PipelineState,
    ) void {
        list.SetGraphicsRootSignature(shader.root_signature);
        if (self.constant_buffer) |*cb| {
            const offset = BufferAlignment * self.swap_chain.currentBackBufferIndex();
            list.SetGraphicsRootConstantBufferView(0, cb.gpuVirtualAddress() + offset);
        }
        list.SetPipelineState(pso);
    }

    fn currentPso(self: *Renderer, shader: *const Shader) ?*win32.ID3D12PipelineState {
        const key = PsoKey{
            .shader_id = shader.id,
            .raster = self.raster_state,
            .depth = self.depth_state,
            .blend = self.blend_mode,
            .topology = self.topology,
        };
        if (self.pso_cache.get(key)) |pso| return pso;

        const pso = self.createPso(shader, key) catch |err| {
            std.log.err("创建 PSO 失败: {s}", .{@errorName(err)});
            return null;
        };
        self.pso_cache.put(std.heap.page_allocator, key, pso) catch {
            _ = pso.IUnknown.Release();
            return null;
        };
        return pso;
    }

    fn createPso(self: *Renderer, shader: *const Shader, key: PsoKey) !*win32.ID3D12PipelineState {
        const blend_enabled = key.blend == .alpha;
        const rt_blend = win32.D3D12_RENDER_TARGET_BLEND_DESC{
            .BlendEnable = if (blend_enabled) 1 else 0,
            .LogicOpEnable = 0,
            .SrcBlend = if (blend_enabled) win32.D3D12_BLEND_SRC_ALPHA else win32.D3D12_BLEND_ONE,
            .DestBlend = if (blend_enabled) win32.D3D12_BLEND_INV_SRC_ALPHA else win32.D3D12_BLEND_ZERO,
            .BlendOp = win32.D3D12_BLEND_OP_ADD,
            .SrcBlendAlpha = win32.D3D12_BLEND_ONE,
            .DestBlendAlpha = win32.D3D12_BLEND_ZERO,
            .BlendOpAlpha = win32.D3D12_BLEND_OP_ADD,
            .LogicOp = win32.D3D12_LOGIC_OP_NOOP,
            .RenderTargetWriteMask = @intFromEnum(win32.D3D12_COLOR_WRITE_ENABLE_ALL),
        };

        var rt_formats: [8]win32.DXGI_FORMAT = @splat(win32.DXGI_FORMAT_UNKNOWN);
        rt_formats[0] = win32.DXGI_FORMAT_R8G8B8A8_UNORM;

        const desc = win32.D3D12_GRAPHICS_PIPELINE_STATE_DESC{
            .pRootSignature = shader.root_signature,
            .VS = .{
                .pShaderBytecode = shader.vs_bytes.ptr,
                .BytecodeLength = shader.vs_bytes.len,
            },
            .PS = .{
                .pShaderBytecode = shader.ps_bytes.ptr,
                .BytecodeLength = shader.ps_bytes.len,
            },
            .DS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
            .HS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
            .GS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
            .StreamOutput = .{
                .pSODeclaration = null,
                .NumEntries = 0,
                .pBufferStrides = null,
                .NumStrides = 0,
                .RasterizedStream = 0,
            },
            .BlendState = .{
                .AlphaToCoverageEnable = 0,
                .IndependentBlendEnable = 0,
                .RenderTarget = @splat(rt_blend),
            },
            .SampleMask = std.math.maxInt(u32),
            .RasterizerState = .{
                .FillMode = switch (key.raster.fill) {
                    .solid => win32.D3D12_FILL_MODE_SOLID,
                    .wireframe => win32.D3D12_FILL_MODE_WIREFRAME,
                },
                .CullMode = switch (key.raster.cull) {
                    .none => win32.D3D12_CULL_MODE_NONE,
                    .front => win32.D3D12_CULL_MODE_FRONT,
                    .back => win32.D3D12_CULL_MODE_BACK,
                },
                .FrontCounterClockwise = if (key.raster.front_counter_clockwise) 1 else 0,
                .DepthBias = 0,
                .DepthBiasClamp = 0.0,
                .SlopeScaledDepthBias = 0.0,
                .DepthClipEnable = 1,
                .MultisampleEnable = 0,
                .AntialiasedLineEnable = 0,
                .ForcedSampleCount = 0,
                .ConservativeRaster = win32.D3D12_CONSERVATIVE_RASTERIZATION_MODE_OFF,
            },
            .DepthStencilState = .{
                .DepthEnable = if (key.depth.depth_test) 1 else 0,
                .DepthWriteMask = if (key.depth.write)
                    win32.D3D12_DEPTH_WRITE_MASK_ALL
                else
                    win32.D3D12_DEPTH_WRITE_MASK_ZERO,
                .DepthFunc = mapCompareFunc(key.depth.compare),
                .StencilEnable = 0,
                .StencilReadMask = 0,
                .StencilWriteMask = 0,
                .FrontFace = default_stencil_op,
                .BackFace = default_stencil_op,
            },
            .InputLayout = .{
                .pInputElementDescs = if (shader.input_elements.len == 0) null else &shader.input_elements[0],
                .NumElements = @intCast(shader.input_elements.len),
            },
            .IBStripCutValue = .DISABLED,
            .PrimitiveTopologyType = switch (key.topology) {
                .triangle_list => win32.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
                .line_list => win32.D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE,
                .point_list => win32.D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT,
            },
            .NumRenderTargets = 1,
            .RTVFormats = rt_formats,
            .DSVFormat = win32.DXGI_FORMAT_D32_FLOAT,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .NodeMask = 0,
            .CachedPSO = .{ .pCachedBlob = null, .CachedBlobSizeInBytes = 0 },
            .Flags = win32.D3D12_PIPELINE_STATE_FLAG_NONE,
        };

        var pso: ?*win32.ID3D12PipelineState = null;
        try Error.check(
            self.device.d3d_device.CreateGraphicsPipelineState(&desc, win32.IID_ID3D12PipelineState, @ptrCast(&pso)),
            "创建图形 PSO",
        );
        return pso.?;
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

const default_stencil_op = win32.D3D12_DEPTH_STENCILOP_DESC{
    .StencilFailOp = win32.D3D12_STENCIL_OP_KEEP,
    .StencilDepthFailOp = win32.D3D12_STENCIL_OP_KEEP,
    .StencilPassOp = win32.D3D12_STENCIL_OP_KEEP,
    .StencilFunc = win32.D3D12_COMPARISON_FUNC.ALWAYS,
};

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

fn mapCompareFunc(func: Types.CompareFunc) win32.D3D12_COMPARISON_FUNC {
    return switch (func) {
        .never => win32.D3D12_COMPARISON_FUNC.NEVER,
        .less => win32.D3D12_COMPARISON_FUNC.LESS,
        .equal => win32.D3D12_COMPARISON_FUNC.EQUAL,
        .less_equal => win32.D3D12_COMPARISON_FUNC.LESS_EQUAL,
        .greater => win32.D3D12_COMPARISON_FUNC.GREATER,
        .not_equal => win32.D3D12_COMPARISON_FUNC.NOT_EQUAL,
        .greater_equal => win32.D3D12_COMPARISON_FUNC.GREATER_EQUAL,
        .always => win32.D3D12_COMPARISON_FUNC.ALWAYS,
    };
}
