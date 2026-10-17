# AGENTS.md

ShadeFlow 分两半：`ShadeFlowNative/`（Zig + D3D11 引擎与窗口）和 `ShadeFlowUI/`（WinUI 3 / C# 宿主）。
根 `Readme.md` 的结构图已部分过时（没有 `engine/core/`，渲染器在 `engine/render/`）。以代码为准。

## 命令（都在 `ShadeFlowNative/` 下执行）

- `zig build` —— 同时产出 `zig-out/bin/ShadeFlowNative.exe`（独立 HWND 模式）和 `ShadeFlowNative.dll`。**仓库没有配置任何测试步骤**，改完靠构建 + 跑起来验证。
- `zig build run` —— 跑独立窗口 demo（窗口/输入改动的常规验证方式）。
- `zig build dll` —— 额外把 DLL 拷到 `../../ShadeFlowUI/`，UI 侧改动生效必须走这个。
- 着色器：`compile_shaders.bat`（cwd 必须是 `ShadeFlowNative`）。脚本里 fxc 路径写死为 `Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe`，SDK 不同要改。产物进 `zig-out/shaders/*VS.cso`；`src/main.zig` 按**exe 目录**找 `..\shaders\...`，所以改了 `assets/shaders/*.hlsl` 必须先重编着色器。
- 工具链：实际安装 Zig 0.17.0；`build.zig.zon` 写 `minimum_zig_version = 0.16.0`；Readme 里的 0.15.2 是过时的。0.17 已删掉的 API 不要再用：`b.args`（改用 `b.option`）、`Allocator.dupeZ` / `std.fmt.allocPrintZ`（用 `allocSentinel` + `@memcpy`）、数组重复 `[N]T{...} ** n` 写法（用 `@splat`）。
- 依赖（`win32`、`windowkit`）被拉到 `zig-pkg/`（gitignore 且按 hash 钉死）。直接改 `zig-pkg/` 里的库源码不是可持续修法；要改库得换成本地 path 依赖或上游 PR。

## ABI / 两模式边界

- `src/main.zig` = 独立 HWND 应用；`src/root.zig` = 给 WinUI 3 的 C-ABI 导出（`ShadeFlow_*`，Composition 模式）。
- `src/root.zig` 的每个 `export fn` 必须和 `ShadeFlowUI/Natives/ShadeFlowNative.cs` 的 `[DllImport(..., CallingConvention.Cdecl)]` 一一对应。`GeometryParams` 是 `extern` 布局的 tagged union，C# 侧用 `[StructLayout(LayoutKind.Explicit)]` 手工对齐——两边任意一侧改字段都要同步。
- `Engine.update` 只在 `self.window == null`（DLL/Composition 由 C# 驱动）时自己泵 Win32 消息；有窗口时消息循环归 windowkit，再泵会重复派发。

## 窗口层（windowkit 适配）— 踩过的坑

- `src/engine/optional/Window.zig` 是 windowkit 的适配层；`Engine.run` 改成 `plat.run()` + 每 vsync 渲染回调，`on_render` 里要 `requestRender()` 才连续出帧。
- windowkit 的 `setUserData` 只有**一个**槽位。适配层在 `init` 里写入 `*Window` 一次，引擎存在 `Window.engine` 字段里。**不要再调 `setUserData`**：回调里 `getUserData(Window)` 会拿到被 `@ptrCast` 成的错误对象，崩溃点会跑到毫不相关的地方（曾表现为 `getScaleFactor()` 返回 1e40 后在 `@intFromFloat` panic）。
- `Window.init` 末尾要显式 `size_changed = true`：windowkit 在 `init` 内部就 `ShowWindow`，旧 WndProc 能看到的 `WM_SIZE` 现在错过了，不补这一下 `Engine.viewport` 永远为 null，点击拾取会静默失效。
- Windows 后端的鼠标坐标是**物理客户区像素**（README 说逻辑像素，与代码不符），不要再乘 `scaleFactor`，否则和物理像素的视口/Picker 对不上。
- `input.zig` 的 `keyCodeFromVirtualKey` 只查 `VK_L*/R*` 修饰键变体，真实键盘来的 `VK_CONTROL/VK_SHIFT/VK_MENU` 会折叠成 `.unknown`：判断 Ctrl/Alt/Shift 要用事件里的 `modifiers` 字段或 `modifiers_changed`，别依赖 `key_down` 的 KeyCode 映射。

## 约定

- 命名按 `fmt.md`：类型 PascalCase、**函数 camelCase（有意偏离 Zig 上游风格）**、变量/字段 snake_case、常量 SCREAMING_SNAKE。
- 注释、日志、提交说明都是中文，保持一致。
- `笔记/` 放设计推导（相机系统、矩阵/投影、万向锁、渲染初始化）。动相机或场景数学前先看对应笔记。
