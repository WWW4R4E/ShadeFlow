//! 图形管线（PSO）。
//!
//! 契约以严格后端为基线：光栅/深度/混合/拓扑连同着色器、顶点布局、render
//! pass 一起烤进一个 `VkPipeline`，在 `createPipeline` 时一次性定型——没有
//! 「随时改状态」这个操作（旧的按状态组合缓存方案随之消亡）。
//!
//! `Pipeline` 借用 `Shader`（shader modules、顶点输入、pipeline layout 都在
//! 那边），**不拥有它**：调用方保证 Shader 比 Pipeline 活得久，析构顺序
//! pipeline → shader。
//!
//! ## Y 轴与绕序
//!
//! 相机的投影矩阵是给 D3D 用的（NDC 的 Y 朝上），直接拿到 Vulkan 会让画面上下
//! 颠倒。这里用**负高度 viewport**（`VK_KHR_maintenance1`，Vulkan 1.1 起是核心）
//! 让视口变换把 NDC +Y 映射到屏幕顶部，与 D3D 完全一致，相机/矩阵代码因此
//! 一行都不用改。深度同理：D3D 与 Vulkan 的 NDC 深度范围都是 0..1。
//!
//! 副作用是屏幕空间的三角形绕序被翻转了，所以 `front_face` 直接跟
//! `front_counter_clockwise` 同名映射——这正是负高度 viewport 下与 D3D
//! `FrontCounterClockwise` 等价的取值（推导见 `mapFrontFace`）。

const std = @import("std");

const vk = @import("vulkan");

const Types = @import("render_types");
const Device = @import("Device.zig").Device;
const Shader = @import("Shader.zig").Shader;

/// 显式管线对象：状态定型后的 `VkPipeline`。
pub const Pipeline = struct {
    /// 借用，不拥有。
    shader: *const Shader,
    state: Types.PipelineState,
    handle: vk.Pipeline,

    pub fn create(shader: *const Shader, state: Types.PipelineState) !Pipeline {
        const handle = try createVk(
            shader.pipeline_context,
            .{ .vertex = shader.vertex_module, .fragment = shader.fragment_module },
            shader.bindings[0..1],
            shader.attributes[0..shader.attribute_count],
            .{
                .topology = state.topology,
                .raster = state.raster,
                .depth = state.depth,
                .blend = state.blend,
            },
        );
        return .{ .shader = shader, .state = state, .handle = handle };
    }

    pub fn deinit(self: *Pipeline) void {
        const shared = self.shader.shared;
        if (self.handle != .null) shared.wrapper.destroyPipeline(shared.device, self.handle, null);
        self.handle = .null;
    }
};

/// 影响 PSO 的那部分管线状态（内部创建参数；公开契约用 `Types.PipelineState`）。
pub const State = struct {
    topology: Types.Topology,
    raster: Types.RasterState,
    depth: Types.DepthState,
    blend: Types.BlendMode,
};

pub const Context = struct {
    shared: *const Device.Shared,
    pipeline_layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
};

pub const Modules = struct {
    vertex: vk.ShaderModule,
    fragment: vk.ShaderModule,
};

pub fn createVk(
    context: Context,
    modules: Modules,
    bindings: []const vk.VertexInputBindingDescription,
    attributes: []const vk.VertexInputAttributeDescription,
    state: State,
) !vk.Pipeline {
    const shared = context.shared;
    const w = &shared.wrapper;

    const stages = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex = true },
            .module = modules.vertex,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment = true },
            .module = modules.fragment,
            .p_name = "main",
        },
    };

    const vertex_input = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = @intCast(bindings.len),
        .p_vertex_binding_descriptions = bindings.ptr,
        .vertex_attribute_description_count = @intCast(attributes.len),
        .p_vertex_attribute_descriptions = attributes.ptr,
    };

    const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = mapTopology(state.topology),
        .primitive_restart_enable = .false,
    };

    // viewport / scissor 是 dynamic state，这里给计数即可，实际值每帧 set。
    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = null,
        .scissor_count = 1,
        .p_scissors = null,
    };

    const raster = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = mapPolygonMode(state.raster.fill, shared.supports_wireframe),
        .cull_mode = mapCullMode(state.raster.cull),
        .front_face = mapFrontFace(state.raster.front_counter_clockwise),
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0.0,
        .depth_bias_clamp = 0.0,
        .depth_bias_slope_factor = 0.0,
        .line_width = 1.0,
    };

    const multisample = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 0.0,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const stencil_off = vk.StencilOpState{
        .fail_op = .keep,
        .pass_op = .keep,
        .depth_fail_op = .keep,
        .compare_op = .always,
        .compare_mask = 0xFF,
        .write_mask = 0xFF,
        .reference = 0,
    };

    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = vk.Bool32.fromBool(state.depth.depth_test),
        .depth_write_enable = vk.Bool32.fromBool(state.depth.write),
        .depth_compare_op = mapCompareFunc(state.depth.compare),
        .depth_bounds_test_enable = .false,
        .stencil_test_enable = .false,
        .front = stencil_off,
        .back = stencil_off,
        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,
    };

    const blend_attachments = [_]vk.PipelineColorBlendAttachmentState{mapBlend(state.blend)};
    const color_blend = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = blend_attachments.len,
        .p_attachments = &blend_attachments,
        .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    const create_info = vk.GraphicsPipelineCreateInfo{
        .stage_count = stages.len,
        .p_stages = &stages,
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &raster,
        .p_multisample_state = &multisample,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blend,
        .p_dynamic_state = &dynamic_state,
        .layout = context.pipeline_layout,
        .render_pass = context.render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null,
        .base_pipeline_index = -1,
    };

    var pipelines: [1]vk.Pipeline = undefined;
    _ = try w.createGraphicsPipelines(shared.device, .null, &.{create_info}, null, &pipelines);
    return pipelines[0];
}

// =============================================================================
// 枚举映射
// =============================================================================

pub fn mapTopology(topology: Types.Topology) vk.PrimitiveTopology {
    return switch (topology) {
        .triangle_list => .triangle_list,
        .line_list => .line_list,
        .point_list => .point_list,
    };
}

/// 负高度 viewport 把屏幕空间的绕序翻了，所以这里的映射与
/// `front_counter_clockwise` 同名：D3D 的 `FrontCounterClockwise=FALSE`
/// （顺时针为正面）对应 Vulkan 的 `.clockwise`。
fn mapFrontFace(counter_clockwise: bool) vk.FrontFace {
    return if (counter_clockwise) .counter_clockwise else .clockwise;
}

fn mapCullMode(cull: Types.CullMode) vk.CullModeFlags {
    return switch (cull) {
        .none => .{},
        .front => .{ .front = true },
        .back => .{ .back = true },
    };
}

/// 线框要 `fillModeNonSolid` 特性；设备不支持时退回实心，避免校验层报错。
fn mapPolygonMode(fill: Types.FillMode, supports_wireframe: bool) vk.PolygonMode {
    return switch (fill) {
        .solid => .fill,
        .wireframe => if (supports_wireframe) .line else .fill,
    };
}

fn mapCompareFunc(func: Types.CompareFunc) vk.CompareOp {
    return switch (func) {
        .never => .never,
        .less => .less,
        .equal => .equal,
        .less_equal => .less_or_equal,
        .greater => .greater,
        .not_equal => .not_equal,
        .greater_equal => .greater_or_equal,
        .always => .always,
    };
}

fn mapBlend(mode: Types.BlendMode) vk.PipelineColorBlendAttachmentState {
    const enabled = mode == .alpha;
    return .{
        .blend_enable = vk.Bool32.fromBool(enabled),
        .src_color_blend_factor = if (enabled) .src_alpha else .one,
        .dst_color_blend_factor = if (enabled) .one_minus_src_alpha else .zero,
        .color_blend_op = .add,
        // 与 D3D11 后端一致：alpha 通道直接取源值。
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r = true, .g = true, .b = true, .a = true },
    };
}
