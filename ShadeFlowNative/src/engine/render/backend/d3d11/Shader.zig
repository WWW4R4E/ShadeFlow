const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Device = @import("Device.zig").Device;
const Error = @import("Error.zig");

/// D3D11 着色器程序：VS + PS + InputLayout。
///
/// 输入布局用后端中立的 `Types.VertexLayout` 描述，`D3D11_INPUT_ELEMENT_DESC`
/// 不再出现在公共接口上。
pub const Shader = struct {
    vertex_shader: ?*win32.ID3D11VertexShader = null,
    pixel_shader: ?*win32.ID3D11PixelShader = null,
    input_layout: ?*win32.ID3D11InputLayout = null,

    /// 输入布局描述过多（栈上固定 16 个槽位）。
    pub const LoadError = error{ TooManyVertexElements, MissingVertexShader, MissingPixelShader };

    /// 从两个已编译的 .cso 文件加载程序。
    ///
    /// 直接用 `std.fs` 读字节，不走 `D3DReadFileToBlob`：省掉 UTF-8 → UTF-16
    /// 路径转换，也让路径处理与平台无关（D3D12 的 DXIL 同样只是字节流）。
    pub fn loadProgram(
        device: *Device,
        vertex_path: []const u8,
        pixel_path: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        const allocator = std.heap.page_allocator;

        const vs_bytes = try readFile(allocator, vertex_path);
        defer allocator.free(vs_bytes);

        const ps_bytes = try readFile(allocator, pixel_path);
        defer allocator.free(ps_bytes);

        return loadFromBytes(device, vs_bytes, ps_bytes, layout);
    }

    pub fn loadFromBytes(
        device: *Device,
        vs_bytes: []const u8,
        ps_bytes: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        if (vs_bytes.len == 0) return error.MissingVertexShader;
        if (ps_bytes.len == 0) return error.MissingPixelShader;

        var shader = Shader{};
        errdefer shader.deinit();

        var vertex_shader: ?*win32.ID3D11VertexShader = null;
        try Error.check(
            device.d3d_device.CreateVertexShader(vs_bytes.ptr, vs_bytes.len, null, @ptrCast(&vertex_shader)),
            "创建顶点着色器",
        );
        shader.vertex_shader = vertex_shader;

        var pixel_shader: ?*win32.ID3D11PixelShader = null;
        try Error.check(
            device.d3d_device.CreatePixelShader(ps_bytes.ptr, ps_bytes.len, null, @ptrCast(&pixel_shader)),
            "创建像素着色器",
        );
        shader.pixel_shader = pixel_shader;

        shader.input_layout = try createInputLayout(device, vs_bytes, layout);
        return shader;
    }

    pub fn use(self: *const Shader, device_context: *win32.ID3D11DeviceContext) void {
        if (self.vertex_shader) |vs| device_context.VSSetShader(vs, null, 0);
        if (self.pixel_shader) |ps| device_context.PSSetShader(ps, null, 0);
        if (self.input_layout) |il| device_context.IASetInputLayout(il);
    }

    pub fn deinit(self: *Shader) void {
        if (self.vertex_shader) |vs| _ = vs.IUnknown.Release();
        if (self.pixel_shader) |ps| _ = ps.IUnknown.Release();
        if (self.input_layout) |il| _ = il.IUnknown.Release();

        self.vertex_shader = null;
        self.pixel_shader = null;
        self.input_layout = null;
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn createInputLayout(
        device: *Device,
        vs_bytes: []const u8,
        layout: Types.VertexLayout,
    ) !*win32.ID3D11InputLayout {
        var descs: [16]win32.D3D11_INPUT_ELEMENT_DESC = undefined;
        if (layout.elements.len > descs.len) return error.TooManyVertexElements;

        for (layout.elements, 0..) |element, i| {
            descs[i] = .{
                .SemanticName = element.semantic.ptr,
                .SemanticIndex = element.semantic_index,
                .Format = mapFormat(element.format),
                .InputSlot = element.input_slot,
                .AlignedByteOffset = element.offset,
                .InputSlotClass = if (element.per_instance)
                    win32.D3D11_INPUT_PER_INSTANCE_DATA
                else
                    win32.D3D11_INPUT_PER_VERTEX_DATA,
                .InstanceDataStepRate = element.instance_step_rate,
            };
        }

        var input_layout: ?*win32.ID3D11InputLayout = null;
        try Error.check(
            device.d3d_device.CreateInputLayout(
                descs[0..layout.elements.len].ptr,
                @intCast(layout.elements.len),
                vs_bytes.ptr,
                vs_bytes.len,
                @ptrCast(&input_layout),
            ),
            "创建输入布局",
        );

        return input_layout.?;
    }

    fn mapFormat(format: Types.Format) win32.DXGI_FORMAT {
        return switch (format) {
            .f32 => win32.DXGI_FORMAT_R32_FLOAT,
            .f32x2 => win32.DXGI_FORMAT_R32G32_FLOAT,
            .f32x3 => win32.DXGI_FORMAT_R32G32B32_FLOAT,
            .f32x4 => win32.DXGI_FORMAT_R32G32B32A32_FLOAT,
            .u32 => win32.DXGI_FORMAT_R32_UINT,
            .u16 => win32.DXGI_FORMAT_R16_UINT,
        };
    }

    fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        // Zig 0.17 起文件 I/O 统一走 std.Io。资产加载是阻塞、低频操作，
        // 用标准库的全局单线程 Io 即可，不必把 Io 一路透传到渲染层。
        const io = std.Io.Threaded.global_single_threaded.io();
        return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    }
};
