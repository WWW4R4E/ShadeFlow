# ShadeFlow 

## 项目概述

ShadeFlow 是一个结合 Zig 原生图形引擎和 WinUI 3 现代界面的图形应用开发框架。项目采用模块化架构，支持实时着色器编辑和可视化节点编程。

## 项目结构

```
ShadeFlow/
├── ShadeFlowNative/          # Zig 原生引擎
│   ├── src/
│   │   ├── engine/
│   │   │   ├── Engine.zig    # 引擎主体（相机/场景对象/主循环）
│   │   │   ├── optional/     # 窗口与输入（windowkit 适配层）
│   │   │   ├── render/       # 渲染门面（Types.zig + Renderer.zig）
│   │   │   │   └── backend/  # 具体后端：d3d11（Windows）/ vulkan（Linux）
│   │   │   ├── scene/        # 变换、对象、几何生成
│   │   │   └── view/         # 相机与拾取
│   │   ├── utils/            # 工具类 (Time.zig、数学库)
│   │   ├── capi.zig          # Windows 专用 C-ABI 导出（WinUI 3 / Composition）
│   │   ├── main.zig          # 独立运行入口
│   │   └── root.zig          # 跨平台引擎入口（exe 与其它 Zig 使用方）
│   ├── assets/shaders/       # HLSL 源码
│   ├── vendor/vk.xml         # Vulkan registry（构建期生成绑定）
│   ├── compile_shaders.bat   # 着色器编译脚本（fxc → .cso）
│   └── build.zig             # Zig 构建配置
├── ShadeFlowUI/              # WinUI 3 界面项目
│   ├── Views/                # 界面视图
│   ├── Controls/             # 自定义控件
│   ├── Models/               # 数据模型
│   └── Natives/              # 原生互操作
└── 笔记/                     # 渲染/相机/矩阵的设计推导
```

## 平台与渲染后端

| 平台 | 渲染后端 | 窗口 |
|---|---|---|
| Windows | Direct3D 11（D3D12 计划中） | WinUI 3 `SwapChainPanel` 或独立 HWND |
| Linux | Vulkan（骨架，待实现） | Wayland（windowkit） |

后端在 `src/engine/render/backend/mod.zig` 按 `builtin.os.tag` 编译期选择；
`Engine` / `scene` 只依赖 `render/Types.zig` 与门面类型，不能直接 import 任何
`backend/<api>/`。


## 核心特性

### 🎯 双模式渲染引擎
- **Composition 模式**: 专为 WinUI 3 集成设计，支持现代 UI 框架
- **HWND 模式**: 传统窗口模式，用于独立测试和调试

### 🎨 实时着色器编辑
- 支持 HLSL 着色器实时编译和预览
- 可视化节点编辑器，所见即所得
- 动态着色器加载，无需重启应用

### 🔧 模块化架构
- 清晰的职责分离：引擎核心、渲染器、资源管理
- 可选的窗口和输入系统，便于集成
- 统一的 C# 互操作接口

## 快速开始

### 环境要求
- Zig 编译器 (0.17.0)
- Windows 10/11 SDK（D3D11 后端）
- Linux：Wayland + `libvulkan.so.1`（运行时加载器）；构建期不需要 Vulkan SDK，绑定由 `vendor/vk.xml` 生成

### 构建 Zig 引擎
```bash
cd ShadeFlowNative
zig build dll    # Windows：构建 DLL 并复制到 ShadeFlowUI
zig build run    # 独立运行测试
zig build typecheck-linux   # 任意主机分析 Linux/Vulkan 分支（只出 object，不链接）
```

### 运行独立测试
```bash
zig build run
```
