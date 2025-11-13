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
    depth_texture: Texture,
    width: u32,
    height: u32,

    pub fn init(hwnd: win32.HWND, width: u32, height: u32) !Renderer {
        // 初始化D3D设备
        var device = try Device.init();

        // 初始化交换链
        const swap_chain = try SwapChain.init(&device, hwnd, width, height);

        // 创建深度模板纹理
        var depth_texture = Texture.init(.depth_stencil);
        try depth_texture.createDepthStencil(&device, width, height);

        // 设置视口
        const viewport = win32.D3D11_VIEWPORT{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(width),
            .Height = @floatFromInt(height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };
        device.getDeviceContext().RSSetViewports(1, @ptrCast(&viewport));

        return Renderer{
            .device = device,
            .swap_chain = swap_chain,
            .depth_texture = depth_texture,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.depth_texture.deinit();
        self.swap_chain.deinit();
        self.device.deinit();
    }

    pub fn beginFrame(self: *Renderer, clear_color: [4]f32) void {
        const device_context = self.device.getDeviceContext();

        // 清除渲染目标和深度模板
        self.swap_chain.clear(device_context, clear_color);
        self.depth_texture.clearDepthStencil(device_context, true, true, 1.0, 0);

        // 设置渲染目标
        self.swap_chain.clear(device_context, clear_color);
    }

    pub fn endFrame(self: *Renderer) void {
        // 呈现交换链
        self.swap_chain.present();
    }

    pub fn getDevice(self: *Renderer) *Device {
        return &self.device;
    }

    pub fn getSwapChain(self: *Renderer) *SwapChain {
        return &self.swap_chain;
    }

    pub fn getDeviceContext(self: *Renderer) *win32.ID3D11DeviceContext {
        return self.device.getDeviceContext();
    }

    // 绘制三角形列表
    pub fn drawTriangleList(self: *Renderer, vertex_count: u32, start_vertex_location: u32) void {
        const device_context = self.device.getDeviceContext();
        device_context.IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        device_context.Draw(vertex_count, start_vertex_location);
    }

    // 绘制索引三角形列表
    pub fn drawIndexedTriangleList(self: *Renderer, index_count: u32, start_index_location: u32, base_vertex_location: i32) void {
        const device_context = self.device.getDeviceContext();
        device_context.IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        device_context.DrawIndexed(index_count, start_index_location, base_vertex_location);
    }

    // 绘制四边形（2D）
    pub fn drawQuad(self: *Renderer, shader: *Shader, vertex_buffer: *Buffer) void {
        const device_context = self.device.getDeviceContext();

        // 使用着色器
        shader.use(device_context);

        // 绑定顶点缓冲区
        vertex_buffer.bindVertexBuffer(device_context, 0);

        // 设置拓扑为三角形列表
        device_context.IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

        // 绘制两个三角形组成的四边形
        device_context.Draw(6, 0);
    }

    // 设置光栅化器状态
    pub fn setRasterizerState(self: *Renderer, fill_mode: enum { solid, wireframe }, cull_mode: enum { none, front, back }) !void {
        const d3d_fill_mode: u32 = switch (fill_mode) {
            .solid => win32.D3D11_FILL_SOLID,
            .wireframe => win32.D3D11_FILL_WIREFRAME,
        };

        const d3d_cull_mode: u32 = switch (cull_mode) {
            .none => win32.D3D11_CULL_NONE,
            .front => win32.D3D11_CULL_FRONT,
            .back => win32.D3D11_CULL_BACK,
        };

        const rasterizer_desc = win32.D3D11_RASTERIZER_DESC{
            .FillMode = d3d_fill_mode,
            .CullMode = d3d_cull_mode,
            .FrontCounterClockwise = false,
            .DepthBias = 0,
            .DepthBiasClamp = 0.0,
            .SlopeScaledDepthBias = 0.0,
            .DepthClipEnable = true,
            .ScissorEnable = false,
            .MultisampleEnable = false,
            .AntialiasedLineEnable = false,
        };

        var rasterizer_state: ?*win32.ID3D11RasterizerState = null;
        if (self.device.d3d_device.CreateRasterizerState(&rasterizer_desc, &rasterizer_state) != win32.S_OK) {
            return error.FailedToCreateRasterizerState;
        }
        defer rasterizer_state.?.Release();

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
    pub fn setDepthStencilState(self: *Renderer, depth_enable: bool, write_enable: bool, comparison_func: enum { never, less, equal, less_equal, greater, not_equal, greater_equal, always }) !void {
        const d3d_comparison_func: u32 = switch (comparison_func) {
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
            .DepthEnable = depth_enable,
            .DepthWriteMask = if (write_enable) win32.D3D11_DEPTH_WRITE_MASK_ALL else win32.D3D11_DEPTH_WRITE_MASK_ZERO,
            .DepthFunc = d3d_comparison_func,
            .StencilEnable = false,
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

        var depth_stencil_state: ?*win32.ID3D11DepthStencilState = null;
        if (self.device.d3d_device.CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state) != win32.S_OK) {
            return error.FailedToCreateDepthStencilState;
        }
        defer depth_stencil_state.?.Release();

        self.device.getDeviceContext().OMSetDepthStencilState(depth_stencil_state, 0);
    }
};
