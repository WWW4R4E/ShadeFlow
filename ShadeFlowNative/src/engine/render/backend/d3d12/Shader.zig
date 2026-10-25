//! D3D12 着色器程序：VS/PS 字节码（DXC 编的 DXIL）+ 输入布局 + 根签名。
//!
//! 与 D3D11 的本质区别：着色器+状态不再各自是独立对象，而是合进一个 PSO。
//! 但 `createShaderFromFiles` 的契约拿不到光栅化/深度/混合状态（它们在
//! Renderer 上、且每帧可变），所以这里只存字节码和布局，PSO 由 Renderer 按
//! 「着色器 × 状态组合」惰性建、带缓存——也就是 AGENTS.md 里说的 PSO 缓存。
//!
//! 根签名固定为一个根 CBV（b0，对所有着色阶段可见）：与 D3D11 后端把常量
//! 缓冲同时绑到 VS/PS 的 b0 槽位一致，HLSL 不用改。

const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Device = @import("Device.zig").Device;
const Error = @import("Error.zig");

// PSO 缓存的键里用 id 而不是指针：Shader 销毁后新 Shader 可能复用同一地址，
// 按地址缓存会把旧 PSO 错配给新着色器。id 单调递增，不会撞。
var next_shader_id: u64 = 0;

pub const Shader = struct {
    id: u64,
    vs_bytes: []u8,
    ps_bytes: []u8,
    /// 输入布局描述（堆分配，deinit 释放）。语义名字指向 Types 里的静态字符串。
    input_elements: []win32.D3D12_INPUT_ELEMENT_DESC,
    root_signature: *win32.ID3D12RootSignature,

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
        var shader: Shader = .{
            .id = nextShaderId(),
            .vs_bytes = vs_bytes,
            .ps_bytes = ps_bytes,
            .input_elements = try allocator.alloc(win32.D3D12_INPUT_ELEMENT_DESC, layout.elements.len),
            .root_signature = undefined,
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

        shader.root_signature = try createRootSignature(device);
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

    fn nextShaderId() u64 {
        next_shader_id += 1;
        return next_shader_id;
    }

    fn createRootSignature(device: *Device) !*win32.ID3D12RootSignature {
        const root_params = [_]win32.D3D12_ROOT_PARAMETER{.{
            .ParameterType = .CBV,
            .Anonymous = .{ .Descriptor = .{ .ShaderRegister = 0, .RegisterSpace = 0 } },
            .ShaderVisibility = .ALL,
        }};
        const desc = win32.D3D12_ROOT_SIGNATURE_DESC{
            .NumParameters = root_params.len,
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
