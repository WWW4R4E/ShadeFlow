//! 着色器程序：SPIR-V 模块 + 顶点输入描述 + 按状态缓存的图形管线。
//!
//! 与 D3D11 后端不同，Vulkan 的「着色器」不只是两个模块：顶点输入布局要进
//! PSO，管线状态（光栅/深度/混合/拓扑）也要一起烤进去。所以这里同时持有
//! 模块和一个按 `Pipeline.State` 键控的 PSO 缓存——`Renderer` 每次切状态
//! 都会调 `getPipeline`，命中就不必重建。
//!
//! 顶点属性的 location 取元素在 `Types.VertexLayout` 里的下标，GLSL 侧用
//! `layout(location = n)` 对齐即可。

const std = @import("std");

const vk = @import("vulkan");

const Types = @import("render_types");
const Buffer = @import("Buffer.zig").Buffer;
const Device = @import("Device.zig").Device;
const Pipeline = @import("Pipeline.zig");

/// 单个 shader 支持的顶点属性数上限（`Types.position_color` 只有 2 个）。
const max_vertex_attributes = 16;

pub const Shader = struct {
    shared: *const Device.Shared,
    vertex_module: vk.ShaderModule,
    fragment_module: vk.ShaderModule,

    bindings: [1]vk.VertexInputBindingDescription,
    attributes: [max_vertex_attributes]vk.VertexInputAttributeDescription,
    attribute_count: u32,

    pipeline_context: Pipeline.Context,
    pipelines: std.AutoHashMap(Pipeline.State, vk.Pipeline),

    pub fn loadProgram(
        pipeline_context: Pipeline.Context,
        vertex_path: []const u8,
        pixel_path: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        const allocator = std.heap.page_allocator;

        const vs_bytes = try readFile(allocator, vertex_path);
        defer allocator.free(vs_bytes);

        const ps_bytes = try readFile(allocator, pixel_path);
        defer allocator.free(ps_bytes);

        return loadFromBytes(pipeline_context, vs_bytes, ps_bytes, layout);
    }

    pub fn loadFromBytes(
        pipeline_context: Pipeline.Context,
        vs_bytes: []const u8,
        ps_bytes: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        const shared = pipeline_context.shared;
        const w = &shared.wrapper;

        if (vs_bytes.len == 0) return error.MissingVertexShader;
        if (ps_bytes.len == 0) return error.MissingPixelShader;

        const vertex_module = try createModule(shared, vs_bytes);
        errdefer w.destroyShaderModule(shared.device, vertex_module, null);

        const fragment_module = try createModule(shared, ps_bytes);
        errdefer w.destroyShaderModule(shared.device, fragment_module, null);

        var shader = Shader{
            .shared = shared,
            .vertex_module = vertex_module,
            .fragment_module = fragment_module,
            .bindings = undefined,
            .attributes = undefined,
            .attribute_count = 0,
            .pipeline_context = pipeline_context,
            .pipelines = .init(std.heap.page_allocator),
        };
        errdefer shader.deinit();

        try buildVertexInput(&shader, layout);
        return shader;
    }

    /// 取（或按需创建）给定状态组合的管线。
    pub fn getPipeline(self: *Shader, state: Pipeline.State) !vk.Pipeline {
        const found = self.pipelines.get(state);
        if (found) |pipeline| return pipeline;

        const pipeline = try Pipeline.create(
            self.pipeline_context,
            .{ .vertex = self.vertex_module, .fragment = self.fragment_module },
            self.bindings[0..1],
            self.attributes[0..self.attribute_count],
            state,
        );
        try self.pipelines.put(state, pipeline);
        return pipeline;
    }

    pub fn deinit(self: *Shader) void {
        const shared = self.shared;
        const w = &shared.wrapper;

        var it = self.pipelines.valueIterator();
        while (it.next()) |pipeline| {
            if (pipeline.* != .null) w.destroyPipeline(shared.device, pipeline.*, null);
        }
        self.pipelines.deinit();

        if (self.vertex_module != .null) w.destroyShaderModule(shared.device, self.vertex_module, null);
        if (self.fragment_module != .null) w.destroyShaderModule(shared.device, self.fragment_module, null);

        self.vertex_module = .null;
        self.fragment_module = .null;
    }

    /// 交换链格式变了导致 render pass 变化时，所有缓存的 PSO 都失效。
    pub fn invalidatePipelines(self: *Shader) void {
        const shared = self.shared;
        const w = &shared.wrapper;

        var it = self.pipelines.valueIterator();
        while (it.next()) |pipeline| {
            if (pipeline.* != .null) w.destroyPipeline(shared.device, pipeline.*, null);
        }
        self.pipelines.clearRetainingCapacity();
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn buildVertexInput(self: *Shader, layout: Types.VertexLayout) !void {
        if (layout.elements.len > self.attributes.len) return error.TooManyVertexElements;

        var slot_count: u32 = 0;
        var slot_strides: [1]u32 = undefined;
        var slot_rates: [1]vk.VertexInputRate = undefined;

        for (layout.elements, 0..) |element, index| {
            // 只支持单一 input slot：引擎当前的两个布局都是如此。
            // 需要多 slot 时把这里换成按 input_slot 去重的表即可。
            if (element.input_slot != 0) return error.MultipleInputSlotsNotSupported;

            if (slot_count == 0) {
                slot_strides[0] = layout.stride;
                slot_rates[0] = if (element.per_instance) .instance else .vertex;
                slot_count = 1;
            }

            self.attributes[index] = .{
                .location = @intCast(index),
                .binding = element.input_slot,
                .format = mapFormat(element.format),
                .offset = element.offset,
            };
        }

        self.attribute_count = @intCast(layout.elements.len);
        if (slot_count == 0) return error.EmptyVertexLayout;
        self.bindings[0] = .{
            .binding = 0,
            .stride = slot_strides[0],
            .input_rate = slot_rates[0],
        };
    }

    fn createModule(shared: *const Device.Shared, bytes: []const u8) !vk.ShaderModule {
        // SPIR-V 是 u32 指令流，文件字节需要补齐到 4 的倍数并保证对齐。
        const allocator = std.heap.page_allocator;
        const words = try allocator.alloc(u32, (bytes.len + 3) / 4);
        defer allocator.free(words);
        @memset(words, 0);
        @memcpy(std.mem.sliceAsBytes(words)[0..bytes.len], bytes);

        if (words.len == 0 or words[0] != spirv_magic) return error.InvalidSpirv;

        return shared.wrapper.createShaderModule(shared.device, &.{
            .code_size = bytes.len,
            .p_code = words.ptr,
        }, null);
    }

    fn mapFormat(format: Types.Format) vk.Format {
        return switch (format) {
            .f32 => .r32_sfloat,
            .f32x2 => .r32g32_sfloat,
            .f32x3 => .r32g32b32_sfloat,
            .f32x4 => .r32g32b32a32_sfloat,
            .u32 => .r32_uint,
            .u16 => .r16_uint,
        };
    }

    /// Zig 0.17 起文件 I/O 统一走 std.Io。资产加载是阻塞、低频操作，
    /// 用标准库的全局单线程 Io 即可，不必把 Io 一路透传到渲染层。
    fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const io = std.Io.Threaded.global_single_threaded.io();
        return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    }
};

const spirv_magic: u32 = 0x07230203;
