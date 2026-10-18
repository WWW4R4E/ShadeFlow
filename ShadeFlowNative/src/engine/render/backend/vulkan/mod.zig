//! Vulkan 后端命名空间（Windows / Win32、Linux / Wayland）。

const Types = @import("render_types");

pub const Renderer = @import("Renderer.zig").Renderer;
pub const Instance = @import("Instance.zig").Instance;
pub const Device = @import("Device.zig").Device;

pub const Buffer = Renderer.Buffer;
pub const Shader = Renderer.Shader;
pub const Texture = Renderer.Texture;

pub const kind: Types.BackendKind = .vulkan;
pub const shader_format: Types.ShaderFormat = .spirv;

pub const capabilities = Types.Capabilities{
    .name = "vulkan",
    // WinUI 的 SwapChainPanel 只认 DXGI 交换链；Vulkan + WinUI 需要
    // external memory / D3D11On12 共享纹理，不属于本后端的 Compose 模式。
    .composition = false,
};
