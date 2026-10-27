# AGENTS.md

ShadeFlow 分两半：`ShadeFlowNative/`（Zig 图形引擎与窗口）和 `ShadeFlowUI/`（WinUI 3 / C# 宿主）。
Windows 默认 Direct3D 12（`-Dbackend=vulkan` 切换）；Linux 走 Vulkan；
macOS 固定走 Vulkan（MoltenVK → Metal），窗口是 AppKit + `CAMetalLayer`。
根 `Readme.md` 的结构图已同步到当前布局（`src/host/` 与 `src/engine/` 两层）；细节以代码为准。

## 命令（都在 `ShadeFlowNative/` 下执行）

- `zig build` —— 当前目标平台的 exe。Windows 上同时产出 `zig-out/bin/ShadeFlowNative.exe`（独立 HWND 模式）和 `ShadeFlowNative.dll`。
- `zig build test` —— 单元测试。宿主侧输入状态 + 引擎侧纯数学（Aabb / Matrix / Picker）+ 顶点布局自洽性 + 资源解析器（`engine/asset/` 的 glTF / PNG，纯 CPU、不碰 GPU；glTF 用例会解析仓库里的 `assets/models/SampleBox.gltf`，文件缺失时自动跳过）。
  - **Zig 只收集「在 test 块里显式引用过」的文件里的测试**，单纯的 import 传递不会把测试带进来（`std/std.zig` 用 `testing.refAllDecls(@This())` 也是这个原因）。所以新增带测试的文件时，必须在 `src/tests.zig` 的 `test` 块里加一行，否则它的用例会**静默不跑**。
  - `render_types` 是独立模块，它的测试不会被 `src/tests.zig` 收进来，`build.zig` 里单独跑一个目标。
- `zig build run` —— 跑独立窗口 demo（窗口/输入改动的常规验证方式）。
- `zig build dll` —— **仅 Windows**：额外把 DLL 拷到 `../../ShadeFlowUI/`，UI 侧改动生效必须走这个。
- `zig build app` —— **仅 macOS**：打包 `zig-out/ShadeFlow.app`（Info.plist + Resources/shaders），`main.zig` 会按 bundle 布局找 `../Resources/shaders`。
- `zig build typecheck-macos` —— 从任意主机交叉分析 macOS 分支（只 `build-obj`，不链接，所以 Linux 上没 macOS SDK 也能过）。改动 `Instance.zig` / `host/Host.zig` / `main.zig` 的 macOS 路径后先跑它。
- 着色器：D3D12 用 `compile_shaders_d3d12.bat`（dxc，SM 6.0，cwd 必须是 `ShadeFlowNative`），脚本里 dxc 路径写死为 `Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe`，SDK 不同要改。产物进 `zig-out/shaders/*VS.cso`；`src/main.zig` 按**exe 目录**找 `..\shaders\...`，所以改了 `assets/shaders/*.hlsl` 必须先重编着色器（Vulkan 侧 glslc 已挂进 `zig build`）。
- 工具链：实际安装 Zig 0.17.0；`build.zig.zon` 写 `minimum_zig_version = 0.16.0`。0.17 已删掉的 API 不要再用：`b.args`（改用 `b.option`）、`Allocator.dupeZ` / `std.fmt.allocPrintZ`（用 `allocSentinel` + `@memcpy`）、数组重复 `[N]T{...} ** n` 写法（用 `@splat`）、`std.fs.cwd()`（改用 `std.Io.Dir.cwd()` + `std.Io`）、`std.time.nanoTimestamp`（改用 `std.Io.Clock.<clock>.now(io)`）。
- 着色器工具链注意：D3D12 用 dxc + SM 6.0（fxc 的 vs_5_0 二进制 D3D12 不认）；Vulkan 用 glslc + SPIR-V（已挂进构建）。
- 依赖（`win32`、`windowkit`、`vulkan`、`zigimg`）被拉到 `zig-pkg/`（gitignore 且按 hash 钉死）。直接改 `zig-pkg/` 里的库源码不是可持续修法；要改库得换成本地 path 依赖或上游 PR。
- 资源加载：`engine/asset/Gltf.zig`（glTF 2.0 → `Engine.addGltfObject`，支持 data URI / 外部文件 / GLB；**每个 primitive 一个渲染对象**：有 baseColorTexture 的 part 走 TEXCOORD_0 + 图片字节（Engine 用 zigimg 解码建纹理），没有的走 COLOR_0 > 材质 baseColorFactor > 白色；RH→LH 转换在解析器里做 X 取反）与 `engine/asset/Png.zig`（zigimg 包装，统一转 RGBA8，顺带支持 JPEG 等格式）。
- 纹理管线：`createTexture(pixels rgba8, w, h)` 上传 GPU；`draw/drawIndexed` 收 `texture: ?*const Texture` 参数，null 绑渲染器的 1×1 白色默认纹理。顶点布局带 `TEXCOORD` 语义时着色器自动切「带纹理变体」（D3D12 根签名多 t0/s0 描述符表，Vulkan 走 set1 combined image sampler，纹理创建时写好描述符）。引擎入口 `Engine.addTexturedIndexedRenderObject`；demo 纹理 `assets/textures/SampleTexture.jpg`（用户的图片副本，会被 git 跟踪）。样例模型/纹理装到 `zig-out/assets/`，`main.zig` 按 exe 目录相对定位（与 shaders/ 同一套逻辑）。
- Vulkan 绑定：`vulkan-zig`（钉在 `zig-0.17-compat` 的 commit，用 codeload tarball URL）。它需要 `vendor/vk.xml`（3.3MB，来自 Vulkan-Headers `registry/vk.xml`）在构建期生成 `vk.zig`。升级 Zig 时要同步换 compat 分支，否则会撞 `standardOptimizeOption` 之类的 API 变化。

## 渲染后端分层（重要）

```
src/engine/render/
  Renderer.zig        ← 门面：pub const Renderer = backend.Renderer（类型别名）
  Types.zig           ← 后端中立的描述类型 + NativeWindow union（独立模块 `render_types`）
  backend/
    mod.zig           ← 转发 build.zig 选定的 `render_backend` + 契约方法检查
    d3d12/            ← Windows（默认；作为独立模块 import win32）
    vulkan/           ← Windows（`-Dbackend=vulkan`）/ Linux / macOS（MoltenVK）
```

- 后端由 `build.zig` 决定：`render_backend` 指向 `d3d12/mod.zig` 或 `vulkan/mod.zig`，未选中的后端不进入模块图。`Types.zig` 作为 `render_types` 模块共享，保证跨模块的 `NativeWindow` 等类型是同一份。
- `Engine.zig`、`scene/`、`engine/root.zig` **只能** import `render/Renderer.zig`；出现 `backend/d3d12/...` 的 import 就是分层回退。
- **契约以「严格后端」为基线（显式管线模型）**：管线状态在 `createPipeline(shader, Types.PipelineState)` 时定型（D3D12 烘进 PSO、Vulkan 烘进 VkPipeline），每 draw 直接传常量（`draw(pipeline, vb, count, constants)`）。没有 setRasterState/setBlendMode/setDepthState/setTopology/setConstants 这类即时上下文残留。新后端必须满足 `backend/mod.zig` 里列出的契约方法 + 转出 `Pipeline` 类型，缺一个在编译期报错。
- `Types.NativeWindow` 与 windowkit 的 `NativeHandles` 字段一一对应，但**独立定义**：转换放在宿主侧（`host/native_handles.zig`），渲染层不依赖 windowkit。
- 资源类型通过门面转出（`Renderer.Buffer/Shader/Pipeline/Texture`）；`scene/Object.zig` 不再 import 后端文件。Object 同时持有 `Shader` 和 `Pipeline`（Pipeline 借用 Shader，析构顺序 pipeline → shader）。
- 常量缓冲由 Renderer 持有（首次 draw 懒创建环形布局），常量随 draw 参数传入，`Engine` 不再管 `Buffer`。
- 后端差异备忘：D3D12 常量缓冲 256 字节对齐（`Constants` 是 224，按 256 一槽）、Vulkan 需要翻转 Y 轴 / 用 SPIR-V。详见 `backend/vulkan/mod.zig` 顶部注释。
- **帧同步差异（待优化项）**：D3D12 每帧 `beginFrame` 里 `waitForGpu`——1 帧 in-flight、「先对后快」；Vulkan 是 2 帧 in-flight（per-frame fence/semaphore/命令缓冲）。后续把 D3D12 的命令分配器/常量环/fence 扩成双缓冲即可对齐。
- Vulkan 的 loader 运行时加载，不在链接期依赖 Vulkan SDK：Windows 走 `LoadLibraryA("vulkan-1.dll")`，Linux 走 `dlopen("libvulkan.so.1")`，macOS 依次尝试 `libMoltenVK.dylib` → `libvulkan.1.dylib` → Homebrew 绝对路径 → `$VULKAN_SDK/lib`。surface 分别是 `VK_KHR_win32_surface` / `VK_KHR_wayland_surface` / `VK_EXT_metal_surface`。
- macOS 专属：`CAMetalLayer` 由 windowkit 创建并同步 `drawableSize`，后端只把它塞进 `VkMetalSurfaceCreateInfoEXT.pLayer`；instance 必须启用 `VK_KHR_portability_enumeration` + `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR`，device 若 advertise `VK_KHR_portability_subset` 就必须一起启用。直接 dlopen MoltenVK 时不会有校验层（校验层只有 loader 能加载），debug 构建里那条 warning 是正常的。
- Vulkan 着色器统一用 `glslc` 编 SPIR-V（`zig build shaders`，已挂进 install）。查找顺序：`-Dglslc=<path>` → PATH → `%VULKAN_SDK%`（Windows `Bin/glslc.exe`，Linux/macOS `bin/glslc`）。

## 宿主 / 引擎边界（重要）

```
src/
├── main.zig      ← 独立窗口宿主：windowkit 窗口 + 事件循环
├── capi.zig      ← WinUI 3 宿主：C-ABI 导出（Composition 模式）
├── tests.zig     ← zig build test 的用例收集根
├── host/         ← 宿主侧：窗口事件 → 引擎命令
│   ├── Host.zig          ← 事件翻译 + 帧边界调度
│   ├── Input.zig         ← 输入状态（按住 / 位置 / 修饰键）
│   └── native_handles.zig← windowkit 句柄 → render 中立句柄
└── engine/       ← 引擎模块（shadeflow_engine）：不认识 windowkit，也不认识输入设备
    ├── root.zig  ← 模块根：跨平台引擎类型出口
    └── …         ← 内部（Engine/scene/view/render/math/Time）一律相对路径
```

- **import 规则一句话：在 `src/engine/` 里 → 相对路径；在外面 → 命名导入 `@import("shadeflow_engine")`。** 这是 Zig 的硬机制（相对路径 import 的文件并入当前模块；跨模块只能用 build.zig 里声明过的命名模块），不是风格偏好。引擎模块名要符合 fmt.md 的 snake_case，不要再用 PascalCase 的 `ShadeFlowNative`（那是 exe/DLL 产物名）。
- 引擎只有**一份模块定义**：exe（`main.zig` + `host/`）和 DLL（`capi.zig`）都以命名模块导入它；`capi_mod` 的 imports 只有 `win32` + `shadeflow_engine`，后端模块（`render_types` / `render_backend`）由引擎模块自己带，不用重复声明。

- **引擎只认命令，不认输入设备**。命令入口：`Engine.cameraZoom` / `cameraPan` / `cameraOrbit` / `cameraSelfRotate` / `pickAt`。独立窗口侧在 `host/Host.zig` 翻译输入，WinUI 侧在 C# 翻译输入，两边调的是同一批函数。
- 引擎模块（`createEngineModule`）**不 import windowkit**，所以 Composition 模式的 DLL 不链接窗口库；windowkit 只挂在 exe 模块上。
- `Engine.update()` 现在是 `void`，不再返回"是否继续"——退出由宿主决定（独立窗口关窗口，WinUI 由 C# 停）。
- 视口在 `Engine.create()` 里就建好（`renderer.width/height`），不再依赖"第一帧恰好触发一次 resize"这种间接手段；拾取依赖 `Engine.viewport`，它从第一帧起就不是 null。

## ABI / 两模式边界

- `src/main.zig` = 独立窗口应用；`src/engine/root.zig` = 引擎模块根（跨平台引擎类型出口）；`src/capi.zig` = WinUI 3 的 C-ABI 导出（`ShadeFlow_*`，Composition 模式），只作为 Windows DLL 的根模块。`ShadeFlowNative.dll` 与 Composition 模式只在 Windows 有意义。
- `ShadeFlow_GetSwapChain` 通过后端中立的 `Renderer.swapChainInteropHandle()` 返回 `?*anyopaque`（D3D12 是 `IDXGISwapChain1*`，非 Direct 后端返回 null）。
- `src/capi.zig` 的每个 `export fn` 必须和 `ShadeFlowUI/Natives/ShadeFlowNative.cs` 的 `[DllImport(..., CallingConvention.Cdecl)]` 一一对应。`GeometryParams` 是 `extern` 布局的 tagged union，C# 侧用 `[StructLayout(LayoutKind.Explicit)]` 手工对齐——两边任意一侧改字段都要同步。
- capi 的能力导出与独立窗口宿主对齐：场景构建（`Add*WithParams` / `AddTexturedCube` / `AddGltfObject`）、相机命令（走 `Engine.cameraZoom/cameraPan/cameraOrbit/cameraSelfRotate` 命令入口，不直接戳 `camera.*`）、拾取与删除（`PickAt` 返回命中索引 / `RemoveRenderObject` 按索引单删，两者同一「枚举顺序」坐标系：render_objects 在前 indexed_render_objects 在后，删除后索引前移，宿主列表要跟着移）。着色器路径参数一律 `?[*:0]const u8`——C# 传 null 时回退 capi 在 `CreateEngineForComposition` 时按**宿主 exe 目录**解析的默认着色器（`shaders/Basic3D*.{cso,spv}`，后缀跟 `shader_format`），所以 C# 侧完全不用管着色器路径。
- `Engine.update` 不泵消息：独立窗口模式由 windowkit 的 `plat.run()` 驱动，WinUI Composition 模式由 `capi.zig` 在每帧 `ShadeFlow_RenderFrame` 里泵 Win32 消息。`ShadeFlow_*` 导出与 `win32` 只存在于 `capi.zig`（仅 Windows 构建），`Engine` 本身是纯跨平台的。
- `Engine` 用 `allocator.create` 分配：销毁用 `engine.destroy()`，不要只 `deinit()`（会漏 Engine 结构体本身）。

## 窗口层（windowkit 适配）— 踩过的坑

- windowkit 的 `setUserData` 只有**一个**槽位。`main.zig` 里写入 `*Host` 一次，之后绝不再调 `setUserData`：回调里 `getUserData(Host)` 会拿到被 `@ptrCast` 成的错误对象，崩溃点会跑到毫不相关的地方（曾表现为 `getScaleFactor()` 返回 1e40 后在 `@intFromFloat` panic）。
- 窗口尺寸变化走"回调置位 + 帧边界重建交换链"：`host/Host.zig` 的 `onResize` 只置 `size_changed`，`onFrame` 里用 `win.framebufferSize()`（**物理**像素）调 `engine.resizeRenderer`。
- Windows 后端的鼠标坐标是**物理客户区像素**（README 说逻辑像素，与代码不符），不要再乘 `scaleFactor`，否则和物理像素的视口/Picker 对不上。归一逻辑在 `host/Host.zig` 的 `toEnginePx`。
- macOS 的 `plat.run()` 是 `[NSApp run]`，关掉窗口不会让它返回：关闭回调里要 `win.getPlatform().quit()`（windowkit 自己的 demo 也这么做）。
- `input.zig` 的 `keyCodeFromVirtualKey` 只查 `VK_L*/R*` 修饰键变体，真实键盘来的 `VK_CONTROL/VK_SHIFT/VK_MENU` 会折叠成 `.unknown`：判断 Ctrl/Alt/Shift 要用事件里的 `modifiers` 字段或 `modifiers_changed`，别依赖 `key_down` 的 KeyCode 映射。

## 输入状态（`src/host/Input.zig`）— 踩过的坑

这三条都是"事件驱动的输入"折算成"帧边界可查询的状态"时容易踩的，改之前先看 `zig build test` 里的用例：

- **鼠标位移必须累加**。写成 `delta = x - last_x` 的话，两次鼠标移动之间只保留最后一次的位移：鼠标频率（120Hz+）高于帧率（60Hz）时会丢掉大部分运动，相机发"顿"。
- **位移只在中键拖动期间累计**，且**中键按下时清零**。否则按下中键的第一帧会把按下之前那段陈旧位移一次性灌进相机（"按下瞬间相机跳一下"）。首次鼠标移动只定锚点、不产生位移——否则启动后第一次移动会从 (0,0) 算起，攒出巨大假位移。
- **一次性输入（滚轮）要记住"事件当下的修饰键"**。滚轮量留到帧边界才消费时，如果这时才去看"现在按着 Ctrl 没有"，会出现"先无 Ctrl 滚一下、再按住 Ctrl，下一帧凭空缩放"。`Input.wheel_modifiers` 就是干这个的。

## 约定

- 命名按 `fmt.md` 编写。
- 注释、日志、提交说明都是中文，保持一致。
- `笔记/` 放设计推导（相机系统、矩阵/投影、万向锁、渲染初始化）。动相机或场景数学前先看对应笔记。
