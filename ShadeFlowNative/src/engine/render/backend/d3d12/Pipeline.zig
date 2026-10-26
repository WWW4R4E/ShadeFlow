//! D3D12 管线对象：创建时把「着色器 × 光栅化/深度/混合/拓扑」一次性烘进 PSO。
//!
//! 这是契约以严格后端为基线的结果：D3D12 没有「随时改状态」这个操作，旧的
//! PsoKey 缓存方案（draw 时按当前状态组合查缓存）随之消亡——状态在
//! `createPipeline` 时就定型了。
//!
//! `Pipeline` 借用 `Shader`（根签名属于 Shader，PSO 创建时已拷贝进去），
//! **不拥有它**：调用方保证 Shader 比 Pipeline 活得久，析构顺序 pipeline
//! → shader。

const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Error = @import("Error.zig");
const Device = @import("Device.zig").Device;
const Shader = @import("Shader.zig").Shader;

pub const Pipeline = struct {
    /// 借用，不拥有。
    shader: *const Shader,
    state: Types.PipelineState,
    pso: *win32.ID3D12PipelineState,

    pub fn create(device: *Device, shader: *const Shader, state: Types.PipelineState) !Pipeline {
        const blend_enabled = state.blend == .alpha;
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
                .FillMode = switch (state.raster.fill) {
                    .solid => win32.D3D12_FILL_MODE_SOLID,
                    .wireframe => win32.D3D12_FILL_MODE_WIREFRAME,
                },
                .CullMode = switch (state.raster.cull) {
                    .none => win32.D3D12_CULL_MODE_NONE,
                    .front => win32.D3D12_CULL_MODE_FRONT,
                    .back => win32.D3D12_CULL_MODE_BACK,
                },
                .FrontCounterClockwise = if (state.raster.front_counter_clockwise) 1 else 0,
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
                .DepthEnable = if (state.depth.depth_test) 1 else 0,
                .DepthWriteMask = if (state.depth.write)
                    win32.D3D12_DEPTH_WRITE_MASK_ALL
                else
                    win32.D3D12_DEPTH_WRITE_MASK_ZERO,
                .DepthFunc = mapCompareFunc(state.depth.compare),
                .StencilEnable = 0,
                .StencilReadMask = 0,
                .StencilWriteMask = 0,
                .FrontFace = default_stencil_op,
                .BackFace = default_stencil_op,
            },
            .InputLayout = .{
                .pInputElementDescs = if (shader.input_elements.len == 0)
                    null
                else
                    &shader.input_elements[0],
                .NumElements = @intCast(shader.input_elements.len),
            },
            .IBStripCutValue = .DISABLED,
            .PrimitiveTopologyType = switch (state.topology) {
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
            device.d3d_device.CreateGraphicsPipelineState(&desc, win32.IID_ID3D12PipelineState, @ptrCast(&pso)),
            "创建图形 PSO",
        );

        return .{ .shader = shader, .state = state, .pso = pso.? };
    }

    pub fn deinit(self: *Pipeline) void {
        _ = self.pso.IUnknown.Release();
        self.pso = undefined;
    }
};

const default_stencil_op = win32.D3D12_DEPTH_STENCILOP_DESC{
    .StencilFailOp = win32.D3D12_STENCIL_OP_KEEP,
    .StencilDepthFailOp = win32.D3D12_STENCIL_OP_KEEP,
    .StencilPassOp = win32.D3D12_STENCIL_OP_KEEP,
    .StencilFunc = win32.D3D12_COMPARISON_FUNC.ALWAYS,
};

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
