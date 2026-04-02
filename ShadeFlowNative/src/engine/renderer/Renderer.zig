const std = @import("std");

const win32 = @import("win32").everything;

const Buffer = @import("d3d11/Buffer.zig").Buffer;
const Device = @import("d3d11/Device.zig").Device;
const Shader = @import("d3d11/Shader.zig").Shader;
const SwapChain = @import("d3d11/SwapChain.zig").SwapChain;
const Texture = @import("d3d11/Texture.zig").Texture;

pub const Renderer = struct {
    device: Device,
    swap_chain: SwapChain,

    // 渲染管线核心资源
    render_target_view: *win32.ID3D11RenderTargetView,
    depth_texture: Texture,
    // 保存 back_buffer 指针通常是个好习惯，虽然 RTV 也持有引用
    back_buffer: *win32.ID3D11Texture2D,

    width: u32,
    height: u32,

    // ============================================================
    // 初始化部分
    // ============================================================

    /// 针对 WinUI 3 (Composition) 的初始化入口
    pub fn initForComposition(width: u32, height: u32) !Renderer {
        // 1. 创建设备
        var device = try Device.init();
        errdefer device.deinit();

        // 2. 创建 SwapChain (Composition 模式)
        // 注意：这里调用的是我们上一轮修改过的 SwapChain.zig
        var swap_chain = try SwapChain.initForComposition(&device, width, height);
        errdefer swap_chain.deinit();

        // 3. 创建其余管线资源 (RTV, Depth, Viewport)
        // 我们先创建一个空的结构体架子，然后调用辅助函数填充资源
        var renderer = Renderer{
            .device = device,
            .swap_chain = swap_chain,
            .render_target_view = undefined,
            .depth_texture = undefined,
            .back_buffer = undefined,
            .width = width,
            .height = height,
        };

        // 这一步会填充 render_target_view, depth_texture 等
        try renderer.createPipelineResources(width, height);

        return renderer;
    }

    /// 针对 原生窗口 (Debug/Standalone) 的初始化入口
    pub fn initForHwnd(hwnd: win32.HWND, width: u32, height: u32) !Renderer {
        var device = try Device.init();
        errdefer device.deinit();

        // 使用 HWND 模式创建 SwapChain
        var swap_chain = try SwapChain.initForHwnd(&device, hwnd, width, height);
        errdefer swap_chain.deinit();

        var renderer = Renderer{
            .device = device,
            .swap_chain = swap_chain,
            .render_target_view = undefined,
            .depth_texture = undefined,
            .back_buffer = undefined,
            .width = width,
            .height = height,
        };
        // 创建管线资源
        try renderer.createPipelineResources(width, height);
        // 启用深度测试和深度写入，使用小于比较函数（默认常用设置）
        // 这意味着：
        // 1. 只有深度值小于深度缓冲区中现有值的像素才会被渲染
        // 2. 通过测试的像素会更新深度缓冲区
        // 3. 实现了正确的遮挡关系，近处物体遮挡远处物体
        // try renderer.setDepthStencilState(true, true, .less);
        // 设置实体填充模式，不剔除任何面（双面渲染），这对于调试很有帮助
        // 这意味着：
        // 1. 实体将以实心模式渲染（而不是线框）
        // 2. 不剔除任何面，无论是正面还是背面
        // try renderer.setRasterizerState(.solid, .none);
        return renderer;
    }

    // ============================================================
    // 资源管理与 Resize
    // ============================================================

    /// 核心辅助函数：创建 RTV, Depth Buffer 和 Viewport
    /// 无论是 Init 还是 Resize，本质上都是在做这件事
    fn createPipelineResources(self: *@This(), width: u32, height: u32) !void {
        // 1. 从 SwapChain 获取 BackBuffer
        // 注意：IDXGISwapChain1 也是用 GetBuffer，接口是一样的
        var back_buffer: *win32.ID3D11Texture2D = undefined;
        const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(self.swap_chain.handle);
        const hr_buffer = swap_chain_base.GetBuffer(0, win32.IID_ID3D11Texture2D, @as(**anyopaque, @ptrCast(&back_buffer)));
        if (hr_buffer != win32.S_OK) return error.FailedToGetBuffer;
        self.back_buffer = back_buffer;

        // 2. 创建 Render Target View
        const back_buffer_resource: ?*win32.ID3D11Resource = @ptrCast(@alignCast(back_buffer));
        if (self.device.d3d_device.CreateRenderTargetView(back_buffer_resource, null, &self.render_target_view) != win32.S_OK) {
            return error.FailedToCreateRenderTargetView;
        }

        // 3. 创建 Depth Stencil Texture
        self.depth_texture = Texture.init(.depth_stencil);
        try self.depth_texture.createDepthStencil(&self.device, width, height);

        // 4. 绑定 Output Merger
        self.device.getDeviceContext().OMSetRenderTargets(1, @ptrCast(&self.render_target_view), self.depth_texture.getDepthStencilView());

        // 5. 设置 Viewport
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

    pub fn deinit(self: *Renderer) void {
        _ = self.device.getDeviceContext().ClearState();

        _ = self.render_target_view.IUnknown.Release();
        _ = self.back_buffer.IUnknown.Release();

        self.depth_texture.deinit();
        self.swap_chain.deinit();
        self.device.deinit();
    }

    // ============================================================
    // Getters & Interop
    // ============================================================

    /// 专门给 C# Interop 使用的方法
    pub fn getSwapChainPointer(self: *Renderer) *anyopaque {
        // 返回 IDXGISwapChain1 的原始指针
        return @ptrCast(self.swap_chain.handle);
    }

    pub fn getDevice(self: *Renderer) *Device {
        return &self.device;
    }

    // ============================================================
    // 渲染逻辑 (保持不变或微调)
    // ============================================================

    pub fn beginFrame(self: *Renderer, clear_color: [4]f32) void {
        self.device.device_context.ClearRenderTargetView(self.render_target_view, @ptrCast(&clear_color));
        self.device.device_context.ClearDepthStencilView(self.depth_texture.getDepthStencilView(), @intFromEnum(win32.D3D11_CLEAR_DEPTH) | @intFromEnum(win32.D3D11_CLEAR_STENCIL), 1.0, 0);
        self.device.device_context.OMSetRenderTargets(1, @ptrCast(&self.render_target_view), self.depth_texture.getDepthStencilView());
        // 渲染普通对象
    }

    pub fn endFrame(self: *Renderer) void {
        self.swap_chain.present();
    }

    pub fn getSwapChain(self: *Renderer) *SwapChain {
        return &self.swap_chain;
    }

    pub fn getDeviceContext(self: *Renderer) *win32.ID3D11DeviceContext {
        return self.device.getDeviceContext();
    }

    // 设置光栅化器状态
    // 参数:
    // - fill_mode: 填充模式，solid为实体填充，wireframe为线框模式
    // - cull_mode: 剔除模式，none不剔除，front剔除正面，back剔除背面
    // 效果:
    // - 控制多边形的渲染方式，如是否显示为实心或线框
    // - 通过剔除不需要的面（如背面）提高渲染性能
    pub fn setRasterizerState(self: *Renderer, fill_mode: enum { solid, wireframe }, cull_mode: enum { none, front, back }) !void {
        const d3d_fill_mode = switch (fill_mode) {
            .solid => win32.D3D11_FILL_SOLID,
            .wireframe => win32.D3D11_FILL_WIREFRAME,
        };

        const d3d_cull_mode = switch (cull_mode) {
            .none => win32.D3D11_CULL_NONE,
            .front => win32.D3D11_CULL_FRONT,
            .back => win32.D3D11_CULL_BACK,
        };

        const rasterizer_desc = win32.D3D11_RASTERIZER_DESC{
            .FillMode = d3d_fill_mode,
            .CullMode = d3d_cull_mode,
            .FrontCounterClockwise = 0,
            .DepthBias = 0,
            .DepthBiasClamp = 0.0,
            .SlopeScaledDepthBias = 0.0,
            .DepthClipEnable = 1,
            .ScissorEnable = 0,
            .MultisampleEnable = 0,
            .AntialiasedLineEnable = 0,
        };

        var rasterizer_state: *win32.ID3D11RasterizerState = undefined;
        if (self.device.d3d_device.CreateRasterizerState(&rasterizer_desc, &rasterizer_state) != win32.S_OK) {
            return error.FailedToCreateRasterizerState;
        }
        defer _ = rasterizer_state.IUnknown.Release();

        self.device.getDeviceContext().RSSetState(rasterizer_state);
    }

    // 设置混合状态
    pub fn setBlendState(self: *Renderer, enabled: bool) !void {
        var blend_desc = win32.D3D11_BLEND_DESC{
            .AlphaToCoverageEnable = false,
            .IndependentBlendEnable = false,
            .RenderTarget = [1]win32.D3D11_RENDER_TARGET_BLEND_DESC{
                win32.D3D11_RENDER_TARGET_BLEND_DESC{
                    .BlendEnable = enabled,
                    .SrcBlend = if (enabled) win32.D3D11_BLEND_SRC_ALPHA else win32.D3D11_BLEND_ONE,
                    .DestBlend = if (enabled) win32.D3D11_BLEND_INV_SRC_ALPHA else win32.D3D11_BLEND_ZERO,
                    .BlendOp = win32.D3D11_BLEND_OP_ADD,
                    .SrcBlendAlpha = win32.D3D11_BLEND_ONE,
                    .DestBlendAlpha = win32.D3D11_BLEND_ZERO,
                    .BlendOpAlpha = win32.D3D11_BLEND_OP_ADD,
                    .RenderTargetWriteMask = win32.D3D11_COLOR_WRITE_ENABLE_ALL,
                },
            },
        };

        var blend_state: ?*win32.ID3D11BlendState = null;
        if (self.device.d3d_device.CreateBlendState(&blend_desc, &blend_state) != win32.S_OK) {
            return error.FailedToCreateBlendState;
        }
        defer blend_state.?.Release();

        const blend_factor: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 };
        self.device.getDeviceContext().OMSetBlendState(blend_state, &blend_factor, 0xFFFFFFFF);
    }

    // 设置深度/模板状态
    // 参数:
    // - depth_enable: 是否启用深度测试
    // - write_enable: 是否启用深度写入
    // - comparison_func: 深度比较函数，决定如何进行深度测试
    // 效果:
    // - 控制深度缓冲区的使用方式，影响物体的遮挡关系
    // - 启用深度测试后，只有通过比较的像素才会被渲染
    // - 启用深度写入后，通过测试的像素会更新深度缓冲区
    pub fn setDepthStencilState(self: *Renderer, depth_enable: bool, write_enable: bool, comparison_func: enum { never, less, equal, less_equal, greater, not_equal, greater_equal, always }) !void {
        const d3d_comparison_func = switch (comparison_func) {
            .never => win32.D3D11_COMPARISON_NEVER,
            .less => win32.D3D11_COMPARISON_LESS,
            .equal => win32.D3D11_COMPARISON_EQUAL,
            .less_equal => win32.D3D11_COMPARISON_LESS_EQUAL,
            .greater => win32.D3D11_COMPARISON_GREATER,
            .not_equal => win32.D3D11_COMPARISON_NOT_EQUAL,
            .greater_equal => win32.D3D11_COMPARISON_GREATER_EQUAL,
            .always => win32.D3D11_COMPARISON_ALWAYS,
        };

        const depth_stencil_desc = win32.D3D11_DEPTH_STENCIL_DESC{
            .DepthEnable = if (depth_enable) 1 else 0,
            .DepthWriteMask = if (write_enable) win32.D3D11_DEPTH_WRITE_MASK_ALL else win32.D3D11_DEPTH_WRITE_MASK_ZERO,
            .DepthFunc = d3d_comparison_func,
            .StencilEnable = 0,
            .StencilReadMask = 0xFF,
            .StencilWriteMask = 0xFF,
            .FrontFace = win32.D3D11_DEPTH_STENCILOP_DESC{
                .StencilFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilDepthFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilPassOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilFunc = win32.D3D11_COMPARISON_ALWAYS,
            },
            .BackFace = win32.D3D11_DEPTH_STENCILOP_DESC{
                .StencilFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilDepthFailOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilPassOp = win32.D3D11_STENCIL_OP_KEEP,
                .StencilFunc = win32.D3D11_COMPARISON_ALWAYS,
            },
        };

        var depth_stencil_state: *win32.ID3D11DepthStencilState = undefined; // 直接用 *T
        if (self.device.d3d_device.CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state) != win32.S_OK) {
            return error.FailedToCreateDepthStencilState;
        }
        defer _ = depth_stencil_state.IUnknown.Release();

        self.device.getDeviceContext().OMSetDepthStencilState(depth_stencil_state, 0);
    }

    // 调整渲染器大小
    pub fn resize(self: *Renderer, width: u32, height: u32) !void {
        // 释放旧资源
        _ = self.render_target_view.IUnknown.Release();
        _ = self.back_buffer.IUnknown.Release();
        self.depth_texture.deinit();

        // 调整交换链大小
        try self.swap_chain.resizeBuffers(width, height);

        // 获取新的后台缓冲区
        const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(self.swap_chain.handle);
        if (swap_chain_base.GetBuffer(0, win32.IID_ID3D11Texture2D, @as(**anyopaque, @ptrCast(&self.back_buffer))) != win32.S_OK) {
            return error.FailedToGetBuffer;
        }

        // 创建新的渲染目标视图
        const back_buffer_resource: ?*win32.ID3D11Resource = @ptrCast(@alignCast(self.back_buffer));
        if (self.device.d3d_device.CreateRenderTargetView(back_buffer_resource, null, &self.render_target_view) != win32.S_OK) {
            return error.FailedToCreateRenderTargetView;
        }

        // 创建新的深度模板纹理
        self.depth_texture = Texture.init(.depth_stencil);
        try self.depth_texture.createDepthStencil(&self.device, width, height);

        // 设置渲染目标
        self.device.getDeviceContext().OMSetRenderTargets(1, @ptrCast(&self.render_target_view), self.depth_texture.getDepthStencilView());

        // 更新视口
        const viewport = win32.D3D11_VIEWPORT{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(width),
            .Height = @floatFromInt(height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };
        self.device.getDeviceContext().RSSetViewports(1, @ptrCast(&viewport));

        // 更新尺寸
        self.width = width;
        self.height = height;
    }
};
