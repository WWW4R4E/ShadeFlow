# ShadeFlow 

## 项目概述

ShadeFlow 是一个结合 Zig 原生图形引擎和 WinUI 3 现代界面的图形应用开发框架。项目采用模块化架构，支持实时着色器编辑和可视化节点编程。

## 项目结构

```
ShadeFlow/
├── ShadeFlowNative/          # Zig 原生引擎
│   ├── src/
│   │   ├── host/             # 宿主侧：窗口事件 → 引擎命令
│   │   │   ├── Host.zig           # 事件翻译 + 帧边界调度
│   │   │   ├── Input.zig          # 输入状态
│   │   │   └── native_handles.zig # windowkit 句柄 → 渲染层中立句柄
│   │   ├── engine/           # 引擎模块（shadeflow_engine）：内部一律相对路径
│   │   │   ├── root.zig      # 模块根：对外的类型出口
│   │   │   ├── Engine.zig    # 引擎主体（只认命令，不认输入设备）
│   │   │   ├── Time.zig      # 帧计时
│   │   │   ├── math/         # Aabb / Matrix / Quaternion（纯数学）
│   │   │   ├── scene/        # 变换、对象、几何生成
│   │   │   ├── view/         # 相机与拾取
│   │   │   └── render/       # 渲染门面（Types.zig + Renderer.zig）
│   │   │       └── backend/  # 具体后端：d3d11（Windows）/ vulkan（Linux、macOS/MoltenVK）
│   │   ├── capi.zig          # Windows 专用 C-ABI 导出（WinUI 3 / Composition）
│   │   ├── main.zig          # 独立窗口宿主入口
│   │   └── tests.zig         # zig build test 的用例收集根
│   ├── assets/shaders/       # HLSL / GLSL 源码
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

### 宿主 / 引擎边界

引擎不认识任何输入设备，只提供 `cameraZoom` / `cameraPan` / `cameraOrbit` /
`cameraSelfRotate` / `pickAt` 几个命令入口：

- **独立窗口模式**：`src/main.zig` 用 windowkit 建窗口，`src/host/Host.zig`
  把窗口事件翻译成引擎命令；
- **Composition 模式**：WinUI 的 XAML 控件捕获输入，C# 侧翻译后调
  `ShadeFlow_Camera*`，最终打到同一批引擎命令入口。

因此引擎模块不链接 windowkit，Composition 模式的 DLL 也不用拖一套窗口库。

## 平台与渲染后端

| 平台 | 渲染后端 | 窗口 |
|---|---|---|
| Windows | Direct3D 11（D3D12 计划中） | WinUI 3 `SwapChainPanel` 或独立 HWND |
| Linux | Vulkan | Wayland（windowkit） |
| macOS | Vulkan（MoltenVK） | AppKit + `CAMetalLayer`（windowkit） |

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
- Vulkan 后端：`glslc`（Vulkan SDK / shaderc；也可用 `-Dglslc=<path>` 指定）
- Linux：Wayland + `libvulkan.so.1`（运行时加载器）；绑定由 `vendor/vk.xml` 生成
- Windows 想跑 Vulkan：内嵌 loader 从 `vulkan-1.dll` 运行时加载，驱动装好即可
- macOS：MoltenVK（Vulkan → Metal）。装法二选一：
  - `brew install molten-vk`（再 `brew install shaderc` 提供 `glslc`）
  - LunarG Vulkan SDK（设置 `VULKAN_SDK`，自带 `libMoltenVK.dylib` 和 `glslc`）

### 构建 Zig 引擎
```bash
cd ShadeFlowNative
zig build dll    # Windows：构建 DLL 并复制到 ShadeFlowUI
zig build run    # 独立运行测试（Windows 默认 D3D11）
zig build run -Dbackend=vulkan   # Windows 切到 Vulkan 后端

# macOS：Vulkan 固定走 MoltenVK
zig build run    # 开发时直接跑 zig-out/bin/ShadeFlowNative
zig build app    # 打包 zig-out/ShadeFlow.app（双击启动）

# 没有 macOS 机器时也能做类型检查
zig build typecheck-macos
```

### 运行独立测试
```bash
zig build run
```
