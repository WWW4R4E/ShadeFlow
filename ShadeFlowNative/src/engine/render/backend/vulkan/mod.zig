//! Vulkan 后端命名空间（Linux / Wayland）。

const Types = @import("../../Types.zig");

pub const Renderer = @import("Renderer.zig").Renderer;
pub const Instance = @import("Instance.zig").Instance;
pub const Device = @import("Device.zig").Device;

pub const Buffer = Renderer.Buffer;
pub const Shader = Renderer.Shader;
pub const Texture = Renderer.Texture;

pub const capabilities = Types.Capabilities{
    .name = "vulkan",
    // WinUI 的 SwapChainPanel 只认 DXGI 交换链；Vulkan + WinUI 需要
    // external memory / D3D11On12 共享纹理，不属于本后端的 Compose 模式。
    .composition = false,
};
