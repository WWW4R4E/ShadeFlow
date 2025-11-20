const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const HResultError = @import("Error.zig").HResultError;

// 纹理类型枚举
pub const TextureType = enum {
    texture_2d,
    texture_cube,
    render_target,
    depth_stencil,
};

pub const Texture = struct {
    texture: ?*win32.ID3D11Texture2D,
    shader_resource_view: ?*win32.ID3D11ShaderResourceView,
    depth_stencil_view: ?*win32.ID3D11DepthStencilView,
    texture_type: TextureType,
    width: u32,
    height: u32,

    pub fn init(texture_type: TextureType) Texture {
        return Texture{
            .texture = null,
            .shader_resource_view = null,
            .depth_stencil_view = null,
            .texture_type = texture_type,
            .width = 0,
            .height = 0,
        };
    }

    pub fn createFromFile(self: *Texture, device: *Device, path: []const u8) HResultError!void {
        // 确保是2D纹理类型
        if (self.texture_type != .texture_2d) {
            return error.InvalidTextureType;
        }

        // 读取文件数据
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const allocator = std.heap.page_allocator;
        const file_data = try allocator.alloc(u8, file_size);
        defer allocator.free(file_data);

        _ = try file.readAll(file_data);

        // 这里简化处理，实际应该解析图像格式（如PNG、JPEG等）
        // 为了演示，我们创建一个简单的纹理描述
        // 注意：真实应用中应该使用图像加载库或实现图像解析

        // 假设我们有一个简单的图像数据（这里只是示例）
        // 在实际应用中，需要解析图像文件格式
        const width: u32 = 256;
        const height: u32 = 256;
        const mip_levels: u32 = 1;

        // 创建纹理描述
        const texture_desc = win32.D3D11_TEXTURE2D_DESC{
            .Width = width,
            .Height = height,
            .MipLevels = mip_levels,
            .ArraySize = 1,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .SampleDesc = .{
                .Count = 1,
                .Quality = 0,
            },
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_SHADER_RESOURCE,
            .CPUAccessFlags = 0,
            .MiscFlags = 0,
        };

        // 创建纹理
        var texture: ?*win32.ID3D11Texture2D = null;
        const hr_tex = device.d3d_device.CreateTexture2D(&texture_desc, null, &texture);
        if (hr_tex != win32.S_OK) {
            return HResultError.init(hr_tex);
        }

        // 创建着色器资源视图
        var shader_resource_view: ?*win32.ID3D11ShaderResourceView = null;
        const srv_desc = win32.D3D11_SHADER_RESOURCE_VIEW_DESC{
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .ViewDimension = win32.D3D11_SRV_DIMENSION_TEXTURE2D,
            .Texture2D = .{
                .MostDetailedMip = 0,
                .MipLevels = mip_levels,
            },
        };

        const hr_srv = device.d3d_device.CreateShaderResourceView(texture.?, &srv_desc, &shader_resource_view);
        if (hr_srv != win32.S_OK) {
            texture.?.Release();
            return HResultError.init(hr_srv);
        }

        // 释放旧资源
        self.deinit();

        // 更新状态
        self.texture = texture;
        self.shader_resource_view = shader_resource_view;
        self.width = width;
        self.height = height;
    }

    pub fn createRenderTarget(self: *Texture, device: *Device, width: u32, height: u32) HResultError!void {
        // 确保是渲染目标类型
        if (self.texture_type != .render_target) {
            return error.InvalidTextureType;
        }

        // 创建渲染目标纹理描述
        const texture_desc = win32.D3D11_TEXTURE2D_DESC{
            .Width = width,
            .Height = height,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .SampleDesc = .{
                .Count = 1,
                .Quality = 0,
            },
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_RENDER_TARGET | win32.D3D11_BIND_SHADER_RESOURCE,
            .CPUAccessFlags = 0,
            .MiscFlags = 0,
        };

        // 创建纹理
        var texture: ?*win32.ID3D11Texture2D = null;
        const hr_tex = device.d3d_device.CreateTexture2D(&texture_desc, null, &texture);
        if (hr_tex != win32.S_OK) {
            return HResultError.init(hr_tex);
        }

        // 创建渲染目标视图
        var render_target_view: ?*win32.ID3D11RenderTargetView = null;
        const rtv_desc = win32.D3D11_RENDER_TARGET_VIEW_DESC{
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .ViewDimension = win32.D3D11_RTV_DIMENSION_TEXTURE2D,
            .Texture2D = .{
                .MipSlice = 0,
            },
        };

        const hr_rtv = device.d3d_device.CreateRenderTargetView(texture.?, &rtv_desc, &render_target_view);
        if (hr_rtv != win32.S_OK) {
            texture.?.Release();
            return HResultError.init(hr_rtv);
        }

        // 释放旧资源
        self.deinit();

        // 更新状态
        self.texture = texture;
        self.render_target_view = render_target_view;
        self.width = width;
        self.height = height;
    }

    pub fn createDepthStencil(self: *Texture, device: *Device, width: u32, height: u32) !void {
        // 确保是深度模板类型
        if (self.texture_type != .depth_stencil) {
            return error.InvalidTextureType;
        }

        // 创建深度模板纹理描述
        const texture_desc = win32.D3D11_TEXTURE2D_DESC{
            .Width = width,
            .Height = height,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = win32.DXGI_FORMAT_D24_UNORM_S8_UINT,
            .SampleDesc = .{
                .Count = 1,
                .Quality = 0,
            },
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_DEPTH_STENCIL,
            .CPUAccessFlags = @bitCast(@as(u32, 0)),
            .MiscFlags = @bitCast(@as(u32, 0)),
        };

        // 创建纹理
        var texture: ?*win32.ID3D11Texture2D = null;
        const hr_tex = device.d3d_device.CreateTexture2D(&texture_desc, null, @ptrCast(&texture));
        if (hr_tex != win32.S_OK) {
            var hr_error: HResultError = undefined;
            hr_error.init(hr_tex);
            return error.HResultError;
        }

        // 创建深度模板视图
        var depth_stencil_view: ?*win32.ID3D11DepthStencilView = null;
        const dsv_desc = win32.D3D11_DEPTH_STENCIL_VIEW_DESC{
            .Format = win32.DXGI_FORMAT_D24_UNORM_S8_UINT,
            .ViewDimension = win32.D3D11_DSV_DIMENSION_TEXTURE2D,
            .Flags = 0,
            .Anonymous = .{
                .Texture2D = .{
                    .MipSlice = 0,
                },
            },
        };

        const hr_dsv = device.d3d_device.CreateDepthStencilView(@ptrCast(texture.?), &dsv_desc, @ptrCast(&depth_stencil_view));
        if (hr_dsv != win32.S_OK) {
            if (texture) |tex| _ = tex.IUnknown.Release();
            var hr_error: HResultError = undefined;
            hr_error.init(hr_dsv);
            return error.HResultError;
        }

        // 释放旧资源
        self.deinit();

        // 更新状态
        self.texture = texture;
        self.depth_stencil_view = depth_stencil_view;
        self.width = width;
        self.height = height;
    }

    pub fn deinit(self: *Texture) void {
        if (self.depth_stencil_view) |dsv| _ = dsv.IUnknown.Release();
        if (self.shader_resource_view) |srv| _ = srv.IUnknown.Release();
        if (self.texture) |tex| _ = tex.IUnknown.Release();

        self.depth_stencil_view = null;
        self.shader_resource_view = null;
        self.texture = null;
    }

    pub fn getDepthStencilView(self: *Texture) ?*win32.ID3D11DepthStencilView {
        return self.depth_stencil_view;
    }
};
