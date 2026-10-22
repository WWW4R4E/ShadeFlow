# AGENTS.md

ShadeFlow 分两半：`ShadeFlowNative/`（Zig 图形引擎与窗口）和 `ShadeFlowUI/`（WinUI 3 / C# 宿主）。
Windows 默认 Direct3D 11（计划迁 D3D12），可用 `-Dbackend=vulkan` 切到 Vulkan；Linux 走 Vulkan；
macOS 固定走 Vulkan（MoltenVK → Metal），窗口是 AppKit + `CAMetalLayer`。
根 `Readme.md` 的结构图已同步到当前布局（`src/host/` 与 `src/engine/` 两层）；细节以代码为准。

## 命令（都在 `ShadeFlowNative/` 下执行）

- `zig build` —— 当前目标平台的 exe。Windows 上同时产出 `zig-out/bin/ShadeFlowNative.exe`（独立 HWND 模式）和 `ShadeFlowNative.dll`。**仓库没有配置任何测试步骤**，改完靠构建 + 跑起来验证。
- `zig build run` —— 跑独立窗口 demo（窗口/输入改动的常规验证方式）。
- `zig build dll` —— **仅 Windows**：额外把 DLL 拷到 `../../ShadeFlowUI/`，UI 侧改动生效必须走这个。
- `zig build app` —— **仅 macOS**：打包 `zig-out/ShadeFlow.app`（Info.plist + Resources/shaders），`main.zig` 会按 bundle 布局找 `../Resources/shaders`。
- `zig build typecheck-macos` —— 从任意主机交叉分析 macOS 分支（只 `build-obj`，不链接，所以 Linux 上没 macOS SDK 也能过）。改动 `Instance.zig` / `host/Host.zig` / `main.zig` 的 macOS 路径后先跑它。
- 着色器：`compile_shaders.bat`（cwd 必须是 `ShadeFlowNative`）。脚本里 fxc 路径写死为 `Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe`，SDK 不同要改。产物进 `zig-out/shaders/*VS.cso`；`src/main.zig` 按**exe 目录**找 `..\shaders\...`，所以改了 `assets/shaders/*.hlsl` 必须先重编着色器。
- 工具链：实际安装 Zig 0.17.0；`build.zig.zon` 写 `minimum_zig_version = 0.16.0`。0.17 已删掉的 API 不要再用：`b.args`（改用 `b.option`）、`Allocator.dupeZ` / `std.fmt.allocPrintZ`（用 `allocSentinel` + `@memcpy`）、数组重复 `[N]T{...} ** n` 写法（用 `@splat`）、`std.fs.cwd()`（改用 `std.Io.Dir.cwd()` + `std.Io`）、`std.time.nanoTimestamp`（改用 `std.Io.Clock.<clock>.now(io)`）。
- 着色器工具链注意：D3D12 落地时 `compile_shaders.bat` 要从 `fxc` 换到 `dxc` + SM 6.x；fxc 产出的 vs_5_0 二进制 D3D12 不认。
- 依赖（`win32`、`windowkit`、`vulkan`）被拉到 `zig-pkg/`（gitignore 且按 hash 钉死）。直接改 `zig-pkg/` 里的库源码不是可持续修法；要改库得换成本地 path 依赖或上游 PR。
- Vulkan 绑定：`vulkan-zig`（钉在 `zig-0.17-compat` 的 commit，用 codeload tarball URL）。它需要 `vendor/vk.xml`（3.3MB，来自 Vulkan-Headers `registry/vk.xml`）在构建期生成 `vk.zig`。升级 Zig 时要同步换 compat 分支，否则会撞 `standardOptimizeOption` 之类的 API 变化。

## 渲染后端分层（重要）

```
src/engine/render/
  Renderer.zig        ← 门面：pub const Renderer = backend.Renderer（类型别名）
  Types.zig           ← 后端中立的描述类型 + NativeWindow union（独立模块 `render_types`）
  backend/
    mod.zig           ← 转发 build.zig 选定的 `render_backend` + 契约方法检查
    d3d11/            ← Windows（默认；作为独立模块 import win32）
    vulkan/           ← Windows（`-Dbackend=vulkan`）/ Linux / macOS（MoltenVK）
```

- 后端由 `build.zig` 决定：`render_backend` 指向 `d3d11/mod.zig` 或 `vulkan/mod.zig`，未选中的后端不进入模块图。`Types.zig` 作为 `render_types` 模块共享，保证跨模块的 `NativeWindow` 等类型是同一份。
- `Engine.zig`、`scene/`、`root.zig`、`host/` **只能** import `render/Renderer.zig`；出现 `backend/d3d11/...` 的 import 就是分层回退。
- 新后端必须满足 `backend/mod.zig` 里列出的契约方法（`initForHwnd` / `beginFrame` / `createVertexBuffer` / `drawIndexed` …），缺一个在编译期报错。
- `Types.NativeWindow` 与 windowkit 的 `NativeHandles` 字段一一对应，但**独立定义**：转换放在宿主侧（`host/native_handles.zig`），渲染层不依赖 windowkit。
- 资源类型通过门面转出（`Renderer.Buffer/Shader/Texture`）；`scene/Object.zig` 不再 import 后端文件。
- `Renderer` 自己持有常量缓冲区（`setConstants` 懒创建），`Engine` 不再管 `Buffer`。
- 后端差异备忘：D3D12 的常量缓冲要 256 字节对齐（当前 `Constants` 是 224，迁移时必须 padding）、状态对象要变成 PSO 缓存、Vulkan 需要翻转 Y 轴 / 用 SPIR-V。详见 `backend/vulkan/mod.zig` 顶部注释。
- Vulkan 的 loader 运行时加载，不在链接期依赖 Vulkan SDK：Windows 走 `LoadLibraryA("vulkan-1.dll")`，Linux 走 `dlopen("libvulkan.so.1")`，macOS 依次尝试 `libMoltenVK.dylib` → `libvulkan.1.dylib` → Homebrew 绝对路径 → `$VULKAN_SDK/lib`。surface 分别是 `VK_KHR_win32_surface` / `VK_KHR_wayland_surface` / `VK_EXT_metal_surface`。
- macOS 专属：`CAMetalLayer` 由 windowkit 创建并同步 `drawableSize`，后端只把它塞进 `VkMetalSurfaceCreateInfoEXT.pLayer`；instance 必须启用 `VK_KHR_portability_enumeration` + `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR`，device 若 advertise `VK_KHR_portability_subset` 就必须一起启用。直接 dlopen MoltenVK 时不会有校验层（校验层只有 loader 能加载），debug 构建里那条 warning 是正常的。
- Vulkan 着色器统一用 `glslc` 编 SPIR-V（`zig build shaders`，已挂进 install）。查找顺序：`-Dglslc=<path>` → PATH → `%VULKAN_SDK%`（Windows `Bin/glslc.exe`，Linux/macOS `bin/glslc`）。

## 宿主 / 引擎边界（重要）

```
src/
├── main.zig      ← 独立窗口宿主：windowkit 窗口 + 事件循环
├── capi.zig      ← WinUI 3 宿主：C-ABI 导出（Composition 模式）
├── root.zig      ← 跨平台引擎类型出口
├── host/         ← 宿主侧：窗口事件 → 引擎命令
│   ├── Host.zig          ← 事件翻译 + 帧边界调度
│   ├── Input.zig         ← 输入状态（按住 / 位置 / 修饰键）
│   └── native_handles.zig← windowkit 句柄 → render 中立句柄
└── engine/       ← 引擎：不认识 windowkit，也不认识任何输入设备
```

- **引擎只认命令，不认输入设备**。命令入口：`Engine.cameraZoom` / `cameraPan` / `cameraOrbit` / `cameraSelfRotate` / `pickAt`。独立窗口侧在 `host/Host.zig` 翻译输入，WinUI 侧在 C# 翻译输入，两边调的是同一批函数。
- 引擎模块（`createEngineModule`）**不 import windowkit**，所以 Composition 模式的 DLL 不链接窗口库；windowkit 只挂在 exe 模块上。
- `Engine.update()` 现在是 `void`，不再返回"是否继续"——退出由宿主决定（独立窗口关窗口，WinUI 由 C# 停）。
- 视口在 `Engine.create()` 里就建好（`renderer.width/height`），不再依赖"第一帧恰好触发一次 resize"这种间接手段；拾取依赖 `Engine.viewport`，它从第一帧起就不是 null。

## ABI / 两模式边界

- `src/main.zig` = 独立窗口应用；`src/root.zig` = 跨平台引擎类型出口；`src/capi.zig` = WinUI 3 的 C-ABI 导出（`ShadeFlow_*`，Composition 模式），只作为 Windows DLL 的根模块。`ShadeFlowNative.dll` 与 Composition 模式只在 Windows 有意义。
- `ShadeFlow_GetSwapChain` 通过后端中立的 `Renderer.swapChainInteropHandle()` 返回 `?*anyopaque`（D3D11 是 `IDXGISwapChain1*`，非 Direct 后端返回 null）。
- `src/capi.zig` 的每个 `export fn` 必须和 `ShadeFlowUI/Natives/ShadeFlowNative.cs` 的 `[DllImport(..., CallingConvention.Cdecl)]` 一一对应。`GeometryParams` 是 `extern` 布局的 tagged union，C# 侧用 `[StructLayout(LayoutKind.Explicit)]` 手工对齐——两边任意一侧改字段都要同步。
- `Engine.update` 不泵消息：独立窗口模式由 windowkit 的 `plat.run()` 驱动，WinUI Composition 模式由 `capi.zig` 在每帧 `ShadeFlow_RenderFrame` 里泵 Win32 消息。`ShadeFlow_*` 导出与 `win32` 只存在于 `capi.zig`（仅 Windows 构建），`Engine` 本身是纯跨平台的。
- `Engine` 用 `allocator.create` 分配：销毁用 `engine.destroy()`，不要只 `deinit()`（会漏 Engine 结构体本身）。

## 窗口层（windowkit 适配）— 踩过的坑

- windowkit 的 `setUserData` 只有**一个**槽位。`main.zig` 里写入 `*Host` 一次，之后绝不再调 `setUserData`：回调里 `getUserData(Host)` 会拿到被 `@ptrCast` 成的错误对象，崩溃点会跑到毫不相关的地方（曾表现为 `getScaleFactor()` 返回 1e40 后在 `@intFromFloat` panic）。
- 窗口尺寸变化走"回调置位 + 帧边界重建交换链"：`host/Host.zig` 的 `onResize` 只置 `size_changed`，`onFrame` 里用 `win.framebufferSize()`（**物理**像素）调 `engine.resizeRenderer`。
- Windows 后端的鼠标坐标是**物理客户区像素**（README 说逻辑像素，与代码不符），不要再乘 `scaleFactor`，否则和物理像素的视口/Picker 对不上。归一逻辑在 `host/Host.zig` 的 `toEnginePx`。
- macOS 的 `plat.run()` 是 `[NSApp run]`，关掉窗口不会让它返回：关闭回调里要 `win.getPlatform().quit()`（windowkit 自己的 demo 也这么做）。
- `input.zig` 的 `keyCodeFromVirtualKey` 只查 `VK_L*/R*` 修饰键变体，真实键盘来的 `VK_CONTROL/VK_SHIFT/VK_MENU` 会折叠成 `.unknown`：判断 Ctrl/Alt/Shift 要用事件里的 `modifiers` 字段或 `modifiers_changed`，别依赖 `key_down` 的 KeyCode 映射。

## 约定

- 命名按 `fmt.md` 编写。
- 注释、日志、提交说明都是中文，保持一致。
- `笔记/` 放设计推导（相机系统、矩阵/投影、万向锁、渲染初始化）。动相机或场景数学前先看对应笔记。
