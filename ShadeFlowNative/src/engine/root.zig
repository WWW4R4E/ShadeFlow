//! 跨平台引擎入口（独立 exe / 其他 Zig 使用方 import 的模块根）。
//!
//! 只导出与平台无关的类型。WinUI 3 的 C-ABI（`ShadeFlow_*`）在 `capi.zig`，
//! 那个文件只在 Windows 上作为 DLL 根模块编译。
//!
//! 引擎不认识 windowkit：窗口与输入在宿主侧（`src/host/`），宿主通过这里
//! 导出的 `Engine` 命令入口驱动引擎。

pub const Engine = @import("Engine.zig").Engine;
pub const Vertex = @import("Engine.zig").Vertex;
pub const Renderer = @import("render/Renderer.zig").Renderer;
/// 渲染后端中立的原生窗口句柄（宿主把 windowkit 的句柄转成它）。
pub const NativeWindow = @import("render/Renderer.zig").NativeWindow;
/// 当前渲染后端的着色器格式（`.dxbc` / `.spirv`）。
pub const shader_format = @import("render/Renderer.zig").shader_format;
pub const GeometryGenerators = @import("scene/GeometryGenerators.zig").GeometryGenerators;
