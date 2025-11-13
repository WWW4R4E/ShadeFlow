const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;

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
        var vertex_shader_ptr = &vertex_shader;
        if (device.d3d_device.CreateVertexShader(shader_data.ptr, shader_data.len, null, @ptrCast(&vertex_shader_ptr)) != win32.S_OK) {
            return error.FailedToCreateVertexShader;
        }

        // 创建输入布局
        var input_layout: ?*win32.ID3D11InputLayout = null;
        var input_layout_ptr = &input_layout;
        if (device.d3d_device.CreateInputLayout(input_elements.ptr, @intCast(input_elements.len), shader_data.ptr, shader_data.len, @ptrCast(&input_layout_ptr)) != win32.S_OK) {
            if (vertex_shader) |vs| _ = vs.IUnknown.Release();
            return error.FailedToCreateInputLayout;
        }

        // 释放旧资源
        if (self.vertex_shader) |vs| _ = vs.IUnknown.Release();
        if (self.input_layout) |il| _ = il.IUnknown.Release();

        self.vertex_shader = vertex_shader;
        self.input_layout = input_layout;
    }

    pub fn loadPixelShader(self: *Shader, device: *Device, shader_data: []const u8) !void {
        var pixel_shader: ?*win32.ID3D11PixelShader = null;
        var pixel_shader_ptr = &pixel_shader;
        if (device.d3d_device.CreatePixelShader(shader_data.ptr, shader_data.len, null, @ptrCast(&pixel_shader_ptr)) != win32.S_OK) {
            return error.FailedToCreatePixelShader;
        }

        // 释放旧资源
        if (self.pixel_shader) |ps| _ = ps.IUnknown.Release();

        self.pixel_shader = pixel_shader;
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
        }
        if (self.pixel_shader) |ps| {
            device_context.PSSetShader(ps, null, 0);
        }
        if (self.input_layout) |il| {
            device_context.IASetInputLayout(il);
        }
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
