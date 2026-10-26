//! D3D12 着色器程序：VS/PS 字节码（DXC 编的 DXIL）+ 输入布局 + 根签名。
//!
//! 着色器只承载「程序 + 输入布局 + 根签名」；光栅化/深度/混合/拓扑由
//! `Pipeline.zig` 在创建时连同这里的字节码一起烘进 PSO。
//!
//! 根签名按顶点布局自动分两种变体（由 `loadProgram` 检查 `TEXCOORD` 语义）：
//! - 基础：根 CBV（b0，全阶段）——现有 position_color 管线用；
//! - 带纹理：根 CBV + 描述符表（t0 SRV、s0 采样器，像素阶段）——
//!   position_texcoord 管线用，`is_textured` 标记，Renderer 据此绑堆。

const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Device = @import("Device.zig").Device;
const Error = @import("Error.zig");

pub const Shader = struct {
    vs_bytes: []u8,
    ps_bytes: []u8,
    /// 输入布局描述（堆分配，deinit 释放）。语义名字指向 Types 里的静态字符串。
    input_elements: []win32.D3D12_INPUT_ELEMENT_DESC,
    root_signature: *win32.ID3D12RootSignature,
    /// 布局含 TEXCOORD → 带纹理变体（根签名多两个描述符表，Renderer 绑堆）。
    is_textured: bool,

    pub const LoadError = error{ TooManyVertexElements, MissingVertexShader, MissingPixelShader, OutOfMemory, HResultFailed };

    pub fn loadProgram(
        device: *Device,
        vertex_path: []const u8,
        pixel_path: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        const allocator = std.heap.page_allocator;

        const vs_bytes = try readFile(allocator, vertex_path);
        errdefer allocator.free(vs_bytes);
        const ps_bytes = try readFile(allocator, pixel_path);
        errdefer allocator.free(ps_bytes);

        return loadFromBytes(device, vs_bytes, ps_bytes, layout);
    }

    pub fn loadFromBytes(
        device: *Device,
        vs_bytes: []u8,
        ps_bytes: []u8,
        layout: Types.VertexLayout,
    ) !Shader {
        if (vs_bytes.len == 0) return error.MissingVertexShader;
        if (ps_bytes.len == 0) return error.MissingPixelShader;
        if (layout.elements.len > 16) return error.TooManyVertexElements;

        const allocator = std.heap.page_allocator;
        const textured = for (layout.elements) |element| {
            if (std.mem.eql(u8, element.semantic, "TEXCOORD")) break true;
        } else false;

        var shader: Shader = .{
            .vs_bytes = vs_bytes,
            .ps_bytes = ps_bytes,
            .input_elements = try allocator.alloc(win32.D3D12_INPUT_ELEMENT_DESC, layout.elements.len),
            .root_signature = undefined,
            .is_textured = textured,
        };
        errdefer {
            allocator.free(shader.input_elements);
            allocator.free(vs_bytes);
            allocator.free(ps_bytes);
        }

        for (layout.elements, 0..) |element, i| {
            shader.input_elements[i] = .{
                .SemanticName = element.semantic.ptr,
                .SemanticIndex = element.semantic_index,
                .Format = mapFormat(element.format),
                .InputSlot = element.input_slot,
                .AlignedByteOffset = element.offset,
                .InputSlotClass = if (element.per_instance)
                    .INSTANCE_DATA
                else
                    .VERTEX_DATA,
                .InstanceDataStepRate = element.instance_step_rate,
            };
        }

        shader.root_signature = try createRootSignature(device, textured);
        return shader;
    }

    pub fn deinit(self: *Shader) void {
        const allocator = std.heap.page_allocator;
        _ = self.root_signature.IUnknown.Release();
        allocator.free(self.input_elements);
        allocator.free(self.vs_bytes);
        allocator.free(self.ps_bytes);
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn createRootSignature(device: *Device, textured: bool) !*win32.ID3D12RootSignature {
        const srv_ranges = [_]win32.D3D12_DESCRIPTOR_RANGE{.{
            .RangeType = .SRV,
            .NumDescriptors = 1,
            .BaseShaderRegister = 0,
            .RegisterSpace = 0,
            .OffsetInDescriptorsFromTableStart = win32.D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND,
        }};
        const sampler_ranges = [_]win32.D3D12_DESCRIPTOR_RANGE{.{
            .RangeType = .SAMPLER,
            .NumDescriptors = 1,
            .BaseShaderRegister = 0,
            .RegisterSpace = 0,
            .OffsetInDescriptorsFromTableStart = win32.D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND,
        }};

        // 0：根 CBV（b0）；带纹理时 1：t0 表、2：s0 表（像素阶段）。
        var root_params: [3]win32.D3D12_ROOT_PARAMETER = undefined;
        root_params[0] = .{
            .ParameterType = .CBV,
            .Anonymous = .{ .Descriptor = .{ .ShaderRegister = 0, .RegisterSpace = 0 } },
            .ShaderVisibility = .ALL,
        };
        var param_count: usize = 1;
        if (textured) {
            root_params[1] = .{
                .ParameterType = .DESCRIPTOR_TABLE,
                .Anonymous = .{ .DescriptorTable = .{ .NumDescriptorRanges = srv_ranges.len, .pDescriptorRanges = &srv_ranges[0] } },
                .ShaderVisibility = win32.D3D12_SHADER_VISIBILITY_PIXEL,
            };
            root_params[2] = .{
                .ParameterType = .DESCRIPTOR_TABLE,
                .Anonymous = .{ .DescriptorTable = .{ .NumDescriptorRanges = sampler_ranges.len, .pDescriptorRanges = &sampler_ranges[0] } },
                .ShaderVisibility = win32.D3D12_SHADER_VISIBILITY_PIXEL,
            };
            param_count = 3;
        }

        const desc = win32.D3D12_ROOT_SIGNATURE_DESC{
            .NumParameters = @intCast(param_count),
            .pParameters = &root_params[0],
            .NumStaticSamplers = 0,
            .pStaticSamplers = null,
            .Flags = win32.D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT,
        };

        var blob: ?*win32.ID3DBlob = null;
        var error_blob: ?*win32.ID3DBlob = null;
        try Error.check(
            win32.D3D12SerializeRootSignature(&desc, win32.D3D_ROOT_SIGNATURE_VERSION_1_0, &blob, &error_blob),
            "序列化根签名",
        );
        defer _ = blob.?.IUnknown.Release();
        defer if (error_blob) |eb| {
            _ = eb.IUnknown.Release();
        };

        const bytes: [*]const u8 = @ptrCast(blob.?.GetBufferPointer().?);
        var root_signature: ?*win32.ID3D12RootSignature = null;
        try Error.check(
            device.d3d_device.CreateRootSignature(
                0,
                bytes,
                blob.?.GetBufferSize(),
                win32.IID_ID3D12RootSignature,
                @ptrCast(&root_signature),
            ),
            "创建根签名",
        );
        return root_signature.?;
    }

    fn mapFormat(format: Types.Format) win32.DXGI_FORMAT {
        return switch (format) {
            .f32 => win32.DXGI_FORMAT_R32_FLOAT,
            .f32x2 => win32.DXGI_FORMAT_R32G32_FLOAT,
            .f32x3 => win32.DXGI_FORMAT_R32G32B32_FLOAT,
            .f32x4 => win32.DXGI_FORMAT_R32G32B32A32_FLOAT,
            .u32 => win32.DXGI_FORMAT_R32_UINT,
        };
    }

    fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const io = std.Io.Threaded.global_single_threaded.io();
        return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    }
};
