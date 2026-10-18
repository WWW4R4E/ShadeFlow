//! 跨平台引擎入口（独立 exe / 其他 Zig 使用方 import 的模块根）。
//!
//! 只导出与平台无关的类型。WinUI 3 的 C-ABI（`ShadeFlow_*`）在 `capi.zig`，
//! 那个文件只在 Windows 上作为 DLL 根模块编译。

pub const Engine = @import("engine/Engine.zig").Engine;
pub const Vertex = @import("engine/Engine.zig").Vertex;
pub const Window = @import("engine/optional/Window.zig").Window;
pub const Renderer = @import("engine/render/Renderer.zig").Renderer;
/// 当前渲染后端的着色器格式（`.dxbc` / `.spirv`）。
pub const shader_format = @import("engine/render/Renderer.zig").shader_format;
pub const GeometryGenerators = @import("engine/scene/GeometryGenerators.zig").GeometryGenerators;
