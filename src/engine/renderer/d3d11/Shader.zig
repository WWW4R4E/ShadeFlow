const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const HResultError = @import("Error.zig").HResultError;

pub const Shader = struct {
    vertex_shader: ?*win32.ID3D11VertexShader,
    pixel_shader: ?*win32.ID3D11PixelShader,
    input_layout: ?*win32.ID3D11InputLayout,
    blob: ?*win32.ID3DBlob,

    pub fn init() Shader {
        return Shader{
            .vertex_shader = null,
            .pixel_shader = null,
            .input_layout = null,
            .blob = null,
        };
    }

    pub fn loadVertexShader(self: *Shader, device: *Device, shader_data: []const u8, input_elements: []const win32.D3D11_INPUT_ELEMENT_DESC) !void {
        // 创建顶点着色器
        var vertex_shader: ?*win32.ID3D11VertexShader = null;
        const hr_vs = device.d3d_device.CreateVertexShader(shader_data.ptr, shader_data.len, null, @ptrCast(&vertex_shader));
        if (hr_vs != win32.S_OK) {
            std.debug.print("Failed to create vertex shader, HRESULT: 0x{X}\n", .{hr_vs});
            var hresult_error: HResultError = undefined;
            hresult_error.init(hr_vs);
            return error.HResultError;
        }
        if (vertex_shader == null) {
            std.debug.print("ERROR: vertex_shader is null after creation\n", .{});
            return error.VertexShaderCreationFailed;
        }
        // 创建输入布局
        var input_layout: ?*win32.ID3D11InputLayout = null;
        const hr_il = device.d3d_device.CreateInputLayout(input_elements.ptr, @intCast(input_elements.len), shader_data.ptr, shader_data.len, @ptrCast(&input_layout));
        if (hr_il != win32.S_OK) {
            std.debug.print("Failed to create input layout, HRESULT: 0x{X}\n", .{hr_il});
            if (vertex_shader) |vs| _ = vs.IUnknown.Release();
            var hresult_error: HResultError = undefined;
            hresult_error.init(hr_il);
            return error.HResultError;
        }
        if (input_layout == null) {
            std.debug.print("ERROR: input_layout is null after creation\n", .{});
            if (vertex_shader) |vs| _ = vs.IUnknown.Release();
            return error.InputLayoutCreationFailed;
        }
        std.debug.print("Successfully created input layout\n", .{});

        // 释放旧资源
        if (self.vertex_shader) |vs| _ = vs.IUnknown.Release();
        if (self.input_layout) |il| _ = il.IUnknown.Release();

        self.vertex_shader = vertex_shader;
        self.input_layout = input_layout;
        std.debug.print("Vertex shader and input layout loaded successfully\n", .{});
    }

    pub fn loadPixelShader(self: *Shader, device: *Device, shader_data: []const u8) !void {
        var pixel_shader: ?*win32.ID3D11PixelShader = null;
        const hr = device.d3d_device.CreatePixelShader(shader_data.ptr, shader_data.len, null, @ptrCast(&pixel_shader));
        std.debug.print("CreatePixelShader HRESULT: 0x{X}\n", .{@as(u32, @bitCast(hr))});
        std.debug.print("Created pixel shader pointer: {*}\n", .{pixel_shader});
        if (hr != win32.S_OK) {
            std.debug.print("Failed to create pixel shader, HRESULT: 0x{X}\n", .{hr});
            var hresult_error: HResultError = undefined;
            hresult_error.init(hr);
            return error.HResultError;
        }
        if (pixel_shader == null) {
            std.debug.print("ERROR: pixel_shader is null after creation\n", .{});
            return error.PixelShaderCreationFailed;
        }

        // 释放旧资源
        if (self.pixel_shader) |ps| _ = ps.IUnknown.Release();

        self.pixel_shader = pixel_shader;
        std.debug.print("Pixel shader loaded successfully\n", .{});
    }

    pub fn loadShaderFromFile(self: *Shader, device: *Device, path: []const u8, shader_type: enum { vertex, pixel }, input_elements: ?[]const win32.D3D11_INPUT_ELEMENT_DESC) !void {
        // 读取着色器文件
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const allocator = std.heap.page_allocator;
        const shader_data = try allocator.alloc(u8, file_size);
        defer allocator.free(shader_data);

        _ = try file.readAll(shader_data);

        // 根据类型加载着色器
        switch (shader_type) {
            .vertex => {
                if (input_elements) |elements| {
                    try self.loadVertexShader(device, shader_data, elements);
                } else {
                    return error.MissingInputLayoutForVertexShader;
                }
            },
            .pixel => {
                try self.loadPixelShader(device, shader_data);
            },
        }
    }

    pub fn use(self: *Shader, device_context: *win32.ID3D11DeviceContext) void {
        if (self.vertex_shader) |vs| {
            device_context.VSSetShader(vs, null, 0);
        } else {
            std.debug.print("No vertex shader to set\n", .{});
        }

        if (self.pixel_shader) |ps| {
            device_context.PSSetShader(ps, null, 0);
        } else {
            std.debug.print("No pixel shader to set\n", .{});
        }

        if (self.input_layout) |il| {
            device_context.IASetInputLayout(il);
        } else {
            std.debug.print("No input layout to set\n", .{});
        }

        device_context.IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

        std.debug.print("Shader use completed\n", .{});
    }

    pub fn deinit(self: *Shader) void {
        if (self.vertex_shader) |vs| _ = vs.IUnknown.Release();
        if (self.pixel_shader) |ps| _ = ps.IUnknown.Release();
        if (self.input_layout) |il| _ = il.IUnknown.Release();
        if (self.blob) |b| _ = b.IUnknown.Release();
    }
};

// 常用的输入布局定义
pub const CommonInputLayouts = struct {
    // 位置+颜色输入布局
    pub fn positionColor() []const win32.D3D11_INPUT_ELEMENT_DESC {
        return &[_]win32.D3D11_INPUT_ELEMENT_DESC{
            .{
                .SemanticName = "POSITION",
                .SemanticIndex = 0,
                .Format = win32.DXGI_FORMAT_R32G32B32_FLOAT,
                .InputSlot = 0,
                .AlignedByteOffset = 0,
                .InputSlotClass = win32.D3D11_INPUT_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
            .{
                .SemanticName = "COLOR",
                .SemanticIndex = 0,
                .Format = win32.DXGI_FORMAT_R32G32B32A32_FLOAT,
                .InputSlot = 0,
                .AlignedByteOffset = 12,
                .InputSlotClass = win32.D3D11_INPUT_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
        };
    }

    // 位置+纹理坐标输入布局
    pub fn positionTexCoord() []const win32.D3D11_INPUT_ELEMENT_DESC {
        return &[_]win32.D3D11_INPUT_ELEMENT_DESC{
            .{
                .SemanticName = "POSITION",
                .SemanticIndex = 0,
                .Format = win32.DXGI_FORMAT_R32G32B32_FLOAT,
                .InputSlot = 0,
                .AlignedByteOffset = 0,
                .InputSlotClass = win32.D3D11_INPUT_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
            .{
                .SemanticName = "TEXCOORD",
                .SemanticIndex = 0,
                .Format = win32.DXGI_FORMAT_R32G32_FLOAT,
                .InputSlot = 0,
                .AlignedByteOffset = 12,
                .InputSlotClass = win32.D3D11_INPUT_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
        };
    }
};
