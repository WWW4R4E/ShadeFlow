//! D3D11（Direct3D 11）后端命名空间。

const Types = @import("render_types");

pub const Renderer = @import("Renderer.zig").Renderer;
pub const Device = @import("Device.zig").Device;
pub const Buffer = @import("Buffer.zig").Buffer;
pub const Shader = @import("Shader.zig").Shader;
pub const Texture = @import("Texture.zig").Texture;
pub const SwapChain = @import("SwapChain.zig").SwapChain;
pub const Error = @import("Error.zig");

pub const kind: Types.BackendKind = .d3d11;
pub const shader_format: Types.ShaderFormat = .dxbc;

pub const capabilities = Types.Capabilities{
    .name = "d3d11",
    .composition = true,
};
