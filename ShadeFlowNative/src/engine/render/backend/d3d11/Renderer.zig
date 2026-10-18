//! D3D11 渲染后端。
//!
//! 对外契约（与 `Types.zig` 一起）由 `render/Renderer.zig` 转出；`Engine` 只
//! 通过那层门面使用它，不再直接接触 `ID3D11Device*`。D3D12 后端实现同名
//! 方法即可，`Engine` / `scene` 不需要改。

const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Error = @import("Error.zig");

const BufferImpl = @import("Buffer.zig").Buffer;
const Device = @import("Device.zig").Device;
const ShaderImpl = @import("Shader.zig").Shader;
const SwapChain = @import("SwapChain.zig").SwapChain;
const TextureImpl = @import("Texture.zig").Texture;

pub const Renderer = struct {
    // 供门面/场景层使用的资源类型（不含任何方法约定上的后端差异）。
    pub const Buffer = BufferImpl;
    pub const Shader = ShaderImpl;
    pub const Texture = TextureImpl;

    device: Device,
    swap_chain: SwapChain,

    render_target_view: ?*win32.ID3D11RenderTargetView = null,
    back_buffer: ?*win32.ID3D11Texture2D = null,
    depth_texture: Texture,

    width: u32,
    height: u32,

    /// 常量缓冲区按第一次 `setConstants` 的大小懒创建。
    constant_buffer: ?Buffer = null,

    // 当前管线状态。D3D11 用独立对象，D3D12 会转成 PSO 键。
    raster_state: Types.RasterState = .{ .fill = .solid, .cull = .none },
    depth_state: Types.DepthState = .{},
    blend_mode: Types.BlendMode = .none,
    topology: Types.Topology = .triangle_list,

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
        self.applyDefaultState();
        return self;
    }

    /// 独立窗口模式（原生句柄来自 `optional/Window.zig`）。
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
        self.applyDefaultState();
        return self;
    }

    /// 两种模式共用同一套默认状态，避免 Composition 与 HWND 画面不一致。
    fn applyDefaultState(self: *Renderer) void {
        self.setRasterState(self.raster_state) catch |err| {
            std.log.err("设置默认光栅化状态失败: {s}", .{@errorName(err)});
        };
        self.setDepthState(self.depth_state) catch |err| {
            std.log.err("设置默认深度状态失败: {s}", .{@errorName(err)});
        };
        self.setBlendMode(self.blend_mode) catch |err| {
            std.log.err("设置默认混合状态失败: {s}", .{@errorName(err)});
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = self.device.getDeviceContext().ClearState();

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
        const context = self.device.getDeviceContext();

        if (self.render_target_view) |rtv| {
            context.ClearRenderTargetView(rtv, @ptrCast(&clear_color));
        }
        if (self.depth_texture.getDepthStencilView()) |dsv| {
            context.ClearDepthStencilView(
                dsv,
                @backingInt(win32.D3D11_CLEAR_DEPTH) | @backingInt(win32.D3D11_CLEAR_STENCIL),
                1.0,
                0,
            );
        }
        self.bindRenderTargets();
    }

    pub fn endFrame(self: *Renderer) void {
        self.swap_chain.present();
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) !void {
        const context = self.device.getDeviceContext();
        // ResizeBuffers 前必须解绑并释放所有后台缓冲区引用。
        context.OMSetRenderTargets(0, null, null);
        context.ClearState();

        self.releasePipelineResources();

        try self.swap_chain.resizeBuffers(width, height);
        try self.createPipelineResources(width, height);
        self.applyDefaultState();

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

    pub fn createIndexBuffer(self: *Renderer, indices: []const u16) !Buffer {
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

    /// 每帧更新常量数据；缓冲区在首次调用时按数据大小创建。
    pub fn setConstants(self: *Renderer, data: []const u8) !void {
        if (self.constant_buffer == null) {
            self.constant_buffer = Buffer.init(.constant);
            // D3D11 要求常量缓冲区大小是 16 的倍数。
            const size: u32 = @intCast(std.mem.alignForward(usize, data.len, 16));
            if (self.constant_buffer) |*cb| {
                try cb.createConstantBuffer(&self.device, size);
            }
        }

        if (self.constant_buffer) |*cb| {
            try cb.updateConstantBuffer(self.device.getDeviceContext(), data);
        }
    }

    // =========================================================================
    // 状态
    // =========================================================================

    pub fn setTopology(self: *Renderer, topology: Types.Topology) void {
        self.topology = topology;
    }

    pub fn setRasterState(self: *Renderer, state: Types.RasterState) !void {
        self.raster_state = state;

        const desc = win32.D3D11_RASTERIZER_DESC{
            .FillMode = switch (state.fill) {
                .solid => win32.D3D11_FILL_SOLID,
                .wireframe => win32.D3D11_FILL_WIREFRAME,
            },
            .CullMode = switch (state.cull) {
                .none => win32.D3D11_CULL_NONE,
                .front => win32.D3D11_CULL_FRONT,
                .back => win32.D3D11_CULL_BACK,
            },
            .FrontCounterClockwise = if (state.front_counter_clockwise) 1 else 0,
            .DepthBias = 0,
            .DepthBiasClamp = 0.0,
            .SlopeScaledDepthBias = 0.0,
            .DepthClipEnable = 1,
            .ScissorEnable = 0,
            .MultisampleEnable = 0,
            .AntialiasedLineEnable = 0,
        };

        var handle: ?*win32.ID3D11RasterizerState = null;
        try Error.check(
            self.device.d3d_device.CreateRasterizerState(&desc, @ptrCast(&handle)),
            "创建光栅化状态",
        );
        defer _ = handle.?.IUnknown.Release();

        self.device.getDeviceContext().RSSetState(handle);
    }

    pub fn setBlendMode(self: *Renderer, mode: Types.BlendMode) !void {
        self.blend_mode = mode;
        const enabled = mode == .alpha;

        const rt_desc = win32.D3D11_RENDER_TARGET_BLEND_DESC{
            .BlendEnable = if (enabled) 1 else 0,
            .SrcBlend = if (enabled) win32.D3D11_BLEND_SRC_ALPHA else win32.D3D11_BLEND_ONE,
            .DestBlend = if (enabled) win32.D3D11_BLEND_INV_SRC_ALPHA else win32.D3D11_BLEND_ZERO,
            .BlendOp = win32.D3D11_BLEND_OP_ADD,
            .SrcBlendAlpha = win32.D3D11_BLEND_ONE,
            .DestBlendAlpha = win32.D3D11_BLEND_ZERO,
            .BlendOpAlpha = win32.D3D11_BLEND_OP_ADD,
            .RenderTargetWriteMask = @backingInt(win32.D3D11_COLOR_WRITE_ENABLE_ALL),
        };

        const desc = win32.D3D11_BLEND_DESC{
            .AlphaToCoverageEnable = 0,
            .IndependentBlendEnable = 0,
            .RenderTarget = @splat(rt_desc),
        };

        var handle: ?*win32.ID3D11BlendState = null;
        try Error.check(
            self.device.d3d_device.CreateBlendState(&desc, @ptrCast(&handle)),
            "创建混合状态",
        );
        defer _ = handle.?.IUnknown.Release();

        const blend_factor: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 };
        self.device.getDeviceContext().OMSetBlendState(handle, @ptrCast(&blend_factor), 0xFFFFFFFF);
    }

    pub fn setDepthState(self: *Renderer, state: Types.DepthState) !void {
        self.depth_state = state;

        const desc = win32.D3D11_DEPTH_STENCIL_DESC{
            .DepthEnable = if (state.depth_test) 1 else 0,
            .DepthWriteMask = if (state.write) win32.D3D11_DEPTH_WRITE_MASK_ALL else win32.D3D11_DEPTH_WRITE_MASK_ZERO,
            .DepthFunc = mapCompareFunc(state.compare),
            .StencilEnable = 0,
            .StencilReadMask = 0xFF,
            .StencilWriteMask = 0xFF,
            .FrontFace = .{
                .StencilFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilDepthFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilPassOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilFunc = win32.D3D11_COMPARISON_ALWAYS,
            },
            .BackFace = .{
                .StencilFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilDepthFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilPassOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilFunc = win32.D3D11_COMPARISON_ALWAYS,
            },
        };

        var handle: ?*win32.ID3D11DepthStencilState = null;
        try Error.check(
            self.device.d3d_device.CreateDepthStencilState(&desc, @ptrCast(&handle)),
            "创建深度/模板状态",
        );
        defer _ = handle.?.IUnknown.Release();

        self.device.getDeviceContext().OMSetDepthStencilState(handle, 0);
    }

    // =========================================================================
    // 绘制
    // =========================================================================

    pub fn draw(self: *Renderer, shader: *const Shader, vertex_buffer: *const Buffer, vertex_count: u32) void {
        const context = self.device.getDeviceContext();

        self.bindConstantBuffer(context);
        shader.use(context);
        vertex_buffer.bindVertexBuffer(context, 0);
        context.IASetPrimitiveTopology(mapTopology(self.topology));
        context.Draw(vertex_count, 0);
    }

    pub fn drawIndexed(
        self: *Renderer,
        shader: *const Shader,
        vertex_buffer: *const Buffer,
        index_buffer: *const Buffer,
        index_count: u32,
    ) void {
        const context = self.device.getDeviceContext();

        self.bindConstantBuffer(context);
        shader.use(context);
        vertex_buffer.bindVertexBuffer(context, 0);
        index_buffer.bindIndexBuffer(context);
        context.IASetPrimitiveTopology(mapTopology(self.topology));
        context.DrawIndexed(index_count, 0, 0);
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn bindConstantBuffer(self: *Renderer, context: *win32.ID3D11DeviceContext) void {
        if (self.constant_buffer) |*cb| {
            cb.bindConstantBufferVS(context, 0);
            cb.bindConstantBufferPS(context, 0);
        }
    }

    fn bindRenderTargets(self: *Renderer) void {
        var rtv = self.render_target_view;
        self.device.getDeviceContext().OMSetRenderTargets(
            1,
            @ptrCast(&rtv),
            self.depth_texture.getDepthStencilView(),
        );
    }

    fn setViewport(self: *Renderer, width: u32, height: u32) void {
        const viewport = win32.D3D11_VIEWPORT{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(width),
            .Height = @floatFromInt(height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };
        self.device.getDeviceContext().RSSetViewports(1, @ptrCast(&viewport));
    }

    fn createPipelineResources(self: *Renderer, width: u32, height: u32) !void {
        const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(self.swap_chain.handle);

        var back_buffer: ?*win32.ID3D11Texture2D = null;
        try Error.check(
            swap_chain_base.GetBuffer(0, win32.IID_ID3D11Texture2D, @as(**anyopaque, @ptrCast(&back_buffer))),
            "获取后台缓冲区",
        );
        errdefer {
            if (back_buffer) |bb| _ = bb.IUnknown.Release();
        }

        var rtv: ?*win32.ID3D11RenderTargetView = null;
        try Error.check(
            self.device.d3d_device.CreateRenderTargetView(@ptrCast(back_buffer.?), null, @ptrCast(&rtv)),
            "创建后台缓冲区 RTV",
        );
        errdefer {
            if (rtv) |view| _ = view.IUnknown.Release();
        }

        var depth = Texture.init(.depth_stencil);
        errdefer depth.deinit();
        try depth.createDepthStencil(&self.device, width, height);

        // 全部成功后再替换旧资源，失败时保持原状。
        self.releasePipelineResources();
        self.back_buffer = back_buffer;
        self.render_target_view = rtv;
        self.depth_texture = depth;

        self.bindRenderTargets();
        self.setViewport(width, height);
    }

    fn releasePipelineResources(self: *Renderer) void {
        if (self.render_target_view) |rtv| _ = rtv.IUnknown.Release();
        if (self.back_buffer) |bb| _ = bb.IUnknown.Release();

        self.render_target_view = null;
        self.back_buffer = null;
        self.depth_texture.deinit();
    }
};

// =============================================================================
// 枚举映射
// =============================================================================

fn mapTopology(topology: Types.Topology) win32.D3D_PRIMITIVE_TOPOLOGY {
    return switch (topology) {
        .triangle_list => win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST,
        .line_list => win32.D3D11_PRIMITIVE_TOPOLOGY_LINELIST,
        .point_list => win32.D3D11_PRIMITIVE_TOPOLOGY_POINTLIST,
    };
}

fn mapCompareFunc(func: Types.CompareFunc) win32.D3D11_COMPARISON_FUNC {
    return switch (func) {
        .never => win32.D3D11_COMPARISON_NEVER,
        .less => win32.D3D11_COMPARISON_LESS,
        .equal => win32.D3D11_COMPARISON_EQUAL,
        .less_equal => win32.D3D11_COMPARISON_LESS_EQUAL,
        .greater => win32.D3D11_COMPARISON_GREATER,
        .not_equal => win32.D3D11_COMPARISON_NOT_EQUAL,
        .greater_equal => win32.D3D11_COMPARISON_GREATER_EQUAL,
        .always => win32.D3D11_COMPARISON_ALWAYS,
    };
}
