# ShadeFlow 

## 项目概述

ShadeFlow 是一个结合 Zig 原生图形引擎和 WinUI 3 现代界面的图形应用开发框架。项目采用模块化架构，目标是支持实时着色器编辑和可视化节点编程。

当前引擎已具备：跨平台渲染（D3D12 / Vulkan）、显式管线抽象、glTF 网格与贴图导入、PNG/JPEG 纹理解码与采样、顶点法线与方向光。

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
│   │   │   ├── asset/        # 资源解析：Gltf.zig（glTF 2.0）/ Png.zig（zigimg）
│   │   │   ├── math/         # Aabb / Matrix / Quaternion（纯数学）
│   │   │   ├── scene/        # 变换、对象、几何生成（含 UV cube）
│   │   │   ├── view/         # 相机与拾取
│   │   │   └── render/       # 渲染门面（Types.zig + Renderer.zig）
│   │   │       └── backend/  # d3d12（Windows 默认）/ vulkan（Linux、macOS/MoltenVK）
│   │   ├── capi.zig          # Windows 专用 C-ABI 导出（WinUI 3 / Composition）
│   │   ├── main.zig          # 独立窗口宿主入口
│   │   └── tests.zig         # zig build test 的用例收集根
│   ├── assets/
│   │   ├── shaders/          # HLSL / GLSL 源码（基础 + 带纹理两套管线）
│   │   ├── models/           # 样例模型（SampleBox.gltf / BoxTextured.glb）
│   │   └── textures/         # 样例贴图
│   ├── vendor/vk.xml         # Vulkan registry（构建期生成绑定）
│   ├── compile_shaders_d3d12.bat  # D3D12 着色器（dxc，SM 6.0）
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
| Windows | Direct3D 12（默认）/ Vulkan | WinUI 3 `SwapChainPanel` 或独立 HWND |
| Linux | Vulkan | Wayland（windowkit） |
| macOS | Vulkan（MoltenVK） | AppKit + `CAMetalLayer`（windowkit） |

- Windows 用 `-Dbackend=vulkan` 切 Vulkan。
- 渲染契约以「严格后端」为基线：管线状态在 `createPipeline` 时定型
  （D3D12 烘进 PSO、Vulkan 烤进 `VkPipeline`），常量与纹理随 draw 参数传入，
  没有 D3D11 式的即时状态修改。
- 帧同步差异备忘：D3D12 当前每帧等 GPU（1 帧 in-flight），Vulkan 是
  2 帧 in-flight；后续把 D3D12 扩成双缓冲对齐。

## 核心特性

### 🎯 双模式渲染引擎
- **Composition 模式**：专为 WinUI 3 集成设计（D3D12 支持，Vulkan 不支持）
- **HWND 模式**：传统窗口模式，用于独立测试和调试

### 📦 资源加载
- **glTF 2.0**：`.gltf` / `.glb` / 内嵌 base64 / 外部 `.bin` / 外部图片；
  每 primitive 一个渲染对象，`baseColorTexture` 贴图走 TEXCOORD 采样路径，
  无贴图时用 `COLOR_0` > 材质 `baseColorFactor` > 白色
- **图片解码**：zigimg（PNG / JPEG / BMP 等），统一转 RGBA8 上传 GPU
- glTF 的右手系 → 引擎左手投影的转换（X 取反）在解析器内完成

### 🎨 渲染
- 两套顶点布局：`POSITION+COLOR+NORMAL`（顶点色）与
  `POSITION+NORMAL+TEXCOORD`（贴图），按布局自动选择着色器变体
- 方向光 half-lambert 光照（常量缓冲传光照方向 + 环境光强度）
- 纹理采样（linear / repeat），无纹理对象绑 1×1 白色默认纹理

### 🔧 模块化架构
- 清晰的职责分离：宿主（窗口/输入）、引擎核心、渲染门面、后端实现
- 后端契约在编译期检查（`backend/mod.zig`），缺方法直接编译失败
- 统一的 C# 互操作接口

## 快速开始

### 环境要求
- Zig 编译器 (0.17.0)
- Windows 10/11 SDK（D3D12 后端用 `dxc` 编着色器，脚本里 SDK 路径写死需按本机调整）
- Vulkan 后端：`glslc`（Vulkan SDK / shaderc；也可用 `-Dglslc=<path>` 指定）
- Linux：Wayland + `libvulkan.so.1`（运行时加载器）；绑定由 `vendor/vk.xml` 生成
- Windows 想跑 Vulkan：内嵌 loader 从 `vulkan-1.dll` 运行时加载，驱动装好即可
- macOS：MoltenVK（Vulkan → Metal）。装法二选一：
  - `brew install molten-vk`（再 `brew install shaderc` 提供 `glslc`）
  - LunarG Vulkan SDK（设置 `VULKAN_SDK`，自带 `libMoltenVK.dylib` 和 `glslc`）

### 构建 Zig 引擎
```bash
cd ShadeFlowNative
zig build run    # Linux/macOS：Vulkan（glslc 自动编 SPIR-V）

# Windows
zig build run    # 默认 D3D12；先跑 compile_shaders_d3d12.bat 编着色器
zig build dll    # 构建 DLL 并复制到 ShadeFlowUI（Composition 模式）
zig build run -Dbackend=vulkan   # 切 Vulkan 后端

# macOS：Vulkan 固定走 MoltenVK
zig build run    # 开发时直接跑 zig-out/bin/ShadeFlowNative
zig build app    # 打包 zig-out/ShadeFlow.app（双击启动）

# 没有 macOS 机器时也能做类型检查
zig build typecheck-macos
```

### 运行单元测试
```bash
zig build test   # 宿主输入状态 + 引擎数学 + 顶点布局自洽 + glTF/PNG 解析器
```
