//! 渲染层门面 —— 上层唯一允许 import 的渲染入口。
//!
//! 目录约定：
//!
//! ```text
//! render/
//!   Renderer.zig      ← 本文件：后端无关的门面（类型 + 能力 + 平台判定）
//!   Types.zig         ← 后端中立的描述类型
//!   backend/
//!     mod.zig         ← 按目标平台/构建选项编译期选后端
//!     d3d11/          ← Windows（默认）
//!     vulkan/         ← Windows（`-Dbackend=vulkan`）/ Linux
//! ```
//!
//! `Engine.zig`、`scene/`、`root.zig` 只 import `render/Renderer.zig`；任何
//! `@import(".../backend/d3d11/...")` 出现在这些文件里都视为分层回退。
//!
//! 这里用类型别名而不是再包一层结构体：与 windowkit 的
//! `Platform = backend.Platform` 一致，编译期单态、零分派开销，同时由
//! `backend/mod.zig` 的契约检查保证各后端方法齐全。

const backend = @import("backend/mod.zig");

pub const Renderer = backend.Renderer;
pub const NativeWindow = backend.NativeWindow;
pub const capabilities = backend.capabilities;

/// 当前后端种类与着色器格式。上层需要「按后端而不是按 OS」分支时用这两个。
pub const Kind = backend.Kind;
pub const kind = backend.kind;
pub const ShaderFormat = backend.ShaderFormat;
pub const shader_format = backend.shader_format;

pub const Buffer = Renderer.Buffer;
pub const Shader = Renderer.Shader;
pub const Texture = Renderer.Texture;

pub const Types = @import("render_types");

pub const is_windows = backend.is_windows;
pub const is_linux = backend.is_linux;
pub const is_macos = backend.is_macos;
