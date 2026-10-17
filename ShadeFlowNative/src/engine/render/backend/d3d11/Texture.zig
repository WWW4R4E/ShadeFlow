const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const Error = @import("Error.zig");

pub const TextureType = enum {
    texture_2d,
    texture_cube,
    render_target,
    depth_stencil,
};

pub const Texture = struct {
    texture: ?*win32.ID3D11Texture2D = null,
    shader_resource_view: ?*win32.ID3D11ShaderResourceView = null,
    render_target_view: ?*win32.ID3D11RenderTargetView = null,
    depth_stencil_view: ?*win32.ID3D11DepthStencilView = null,
    texture_type: TextureType,
    width: u32 = 0,
    height: u32 = 0,

    pub fn init(texture_type: TextureType) Texture {
        return .{ .texture_type = texture_type };
    }

    /// TODO: 真正解析图片文件（PNG/JPEG）。目前只是建一张空纹理占位，
    /// 这也是为什么它还没有被任何渲染路径调用。
    pub fn createFromFile(self: *Texture, device: *Device, path: []const u8) !void {
        if (self.texture_type != .texture_2d) return error.InvalidTextureType;

        const file = try std.fs.cwd().openFile(path, .{});
        file.close();

        const width: u32 = 256;
        const height: u32 = 256;
        const mip_levels: u32 = 1;

        const desc = win32.D3D11_TEXTURE2D_DESC{
            .Width = width,
            .Height = height,
            .MipLevels = mip_levels,
            .ArraySize = 1,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_SHADER_RESOURCE,
            .CPUAccessFlags = 0,
            .MiscFlags = 0,
        };

        var texture: ?*win32.ID3D11Texture2D = null;
        try Error.check(device.d3d_device.CreateTexture2D(&desc, null, @ptrCast(&texture)), "创建 2D 纹理");

        var srv: ?*win32.ID3D11ShaderResourceView = null;
        const srv_desc = win32.D3D11_SHADER_RESOURCE_VIEW_DESC{
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .ViewDimension = win32.D3D11_SRV_DIMENSION_TEXTURE2D,
            .Texture2D = .{ .MostDetailedMip = 0, .MipLevels = mip_levels },
        };
        Error.check(
            device.d3d_device.CreateShaderResourceView(@ptrCast(texture.?), &srv_desc, @ptrCast(&srv)),
            "创建 SRV",
        ) catch |err| {
            _ = texture.?.IUnknown.Release();
            return err;
        };

        self.deinit();
        self.texture = texture;
        self.shader_resource_view = srv;
        self.width = width;
        self.height = height;
    }

    pub fn createRenderTarget(self: *Texture, device: *Device, width: u32, height: u32) !void {
        if (self.texture_type != .render_target) return error.InvalidTextureType;

        const desc = win32.D3D11_TEXTURE2D_DESC{
            .Width = width,
            .Height = height,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_RENDER_TARGET | win32.D3D11_BIND_SHADER_RESOURCE,
            .CPUAccessFlags = 0,
            .MiscFlags = 0,
        };

        var texture: ?*win32.ID3D11Texture2D = null;
        try Error.check(device.d3d_device.CreateTexture2D(&desc, null, @ptrCast(&texture)), "创建渲染目标纹理");

        var rtv: ?*win32.ID3D11RenderTargetView = null;
        const rtv_desc = win32.D3D11_RENDER_TARGET_VIEW_DESC{
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .ViewDimension = win32.D3D11_RTV_DIMENSION_TEXTURE2D,
            .Texture2D = .{ .MipSlice = 0 },
        };
        Error.check(
            device.d3d_device.CreateRenderTargetView(@ptrCast(texture.?), &rtv_desc, @ptrCast(&rtv)),
            "创建 RTV",
        ) catch |err| {
            _ = texture.?.IUnknown.Release();
            return err;
        };

        self.deinit();
        self.texture = texture;
        self.render_target_view = rtv;
        self.width = width;
        self.height = height;
    }

    pub fn createDepthStencil(self: *Texture, device: *Device, width: u32, height: u32) !void {
        if (self.texture_type != .depth_stencil) return error.InvalidTextureType;

        const desc = win32.D3D11_TEXTURE2D_DESC{
            .Width = width,
            .Height = height,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = win32.DXGI_FORMAT_D24_UNORM_S8_UINT,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_DEPTH_STENCIL,
            .CPUAccessFlags = @bitCast(@as(u32, 0)),
            .MiscFlags = @bitCast(@as(u32, 0)),
        };

        var texture: ?*win32.ID3D11Texture2D = null;
        try Error.check(device.d3d_device.CreateTexture2D(&desc, null, @ptrCast(&texture)), "创建深度纹理");

        var dsv: ?*win32.ID3D11DepthStencilView = null;
        const dsv_desc = win32.D3D11_DEPTH_STENCIL_VIEW_DESC{
            .Format = win32.DXGI_FORMAT_D24_UNORM_S8_UINT,
            .ViewDimension = win32.D3D11_DSV_DIMENSION_TEXTURE2D,
            .Flags = 0,
            .Anonymous = .{ .Texture2D = .{ .MipSlice = 0 } },
        };
        Error.check(
            device.d3d_device.CreateDepthStencilView(@ptrCast(texture.?), &dsv_desc, @ptrCast(&dsv)),
            "创建 DSV",
        ) catch |err| {
            _ = texture.?.IUnknown.Release();
            return err;
        };

        self.deinit();
        self.texture = texture;
        self.depth_stencil_view = dsv;
        self.width = width;
        self.height = height;
    }

    pub fn deinit(self: *Texture) void {
        if (self.depth_stencil_view) |dsv| _ = dsv.IUnknown.Release();
        if (self.render_target_view) |rtv| _ = rtv.IUnknown.Release();
        if (self.shader_resource_view) |srv| _ = srv.IUnknown.Release();
        if (self.texture) |tex| _ = tex.IUnknown.Release();

        self.depth_stencil_view = null;
        self.render_target_view = null;
        self.shader_resource_view = null;
        self.texture = null;
    }

    pub fn getDepthStencilView(self: *Texture) ?*win32.ID3D11DepthStencilView {
        return self.depth_stencil_view;
    }

    pub fn getRenderTargetView(self: *Texture) ?*win32.ID3D11RenderTargetView {
        return self.render_target_view;
    }
};
