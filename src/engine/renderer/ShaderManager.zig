const std = @import("std");
const win32 = @import("win32").everything;

const Shader = @import("d3d11/Shader.zig").Shader;
const Device = @import("d3d11/Device.zig").Device;

pub const ShaderManager = struct {
    allocator: std.mem.Allocator,
    shaders: std.StringHashMap(Shader),
    device: *Device,

    pub fn init(allocator: std.mem.Allocator, device: *Device) ShaderManager {
        return ShaderManager{
            .allocator = allocator,
            .shaders = std.StringHashMap(Shader).init(allocator),
            .device = device,
        };
    }

    pub fn deinit(self: *ShaderManager) void {
        var it = self.shaders.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.shaders.deinit();
    }

    /// 加载顶点着色器和像素着色器组合
    pub fn loadShaderProgram(self: *ShaderManager, name: []const u8, vertex_path: []const u8, pixel_path: []const u8, input_elements: []const win32.D3D11_INPUT_ELEMENT_DESC) !void {
        var shader = Shader.init();

        // 加载顶点着色器
        try shader.loadShaderFromFile(self.device, vertex_path, .vertex, input_elements);
        
        // 加载像素着色器
        try shader.loadShaderFromFile(self.device, pixel_path, .pixel, null);

        // 存储着色器程序
        try self.shaders.put(try self.allocator.dupe(u8, name), shader);
    }

    /// 获取着色器程序
    pub fn getShader(self: *ShaderManager, name: []const u8) ?*Shader {
        return self.shaders.getPtr(name);
    }

    /// 使用指定的着色器程序
    pub fn useShader(self: *ShaderManager, name: []const u8, device_context: *win32.ID3D11DeviceContext) void {
        if (self.shaders.getPtr(name)) |shader| {
            shader.use(device_context);
        }
    }
};