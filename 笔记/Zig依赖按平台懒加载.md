# Zig 依赖按平台懒加载：别让 win32 拖累 Linux / macOS

## 问题现象

在 mac / Linux 上跑 `zig build run`，也会把 `zigwin32` 拉下来，项目里的 `zig-pkg/win32-25.0.28-preview-.../` 总会出现。

`ShadeFlowNative/build.zig` 里其实已经按平台分支了（`win32` 只给 Windows 的 D3D11 后端和 `capi.zig` 用），但**光改 build.zig 没用**。

## 根因（两件事，必须一起处理）

### 1. `build.zig.zon` 里的依赖默认是 eager 的

`lib/compiler/Maker/Package/Manifest.zig` 解析 `dependencies` 时 `lazy` 默认 `false`；`Maker/Fetch.zig` 里 `Mode.needed`（`zig build` 的默认模式）对非 lazy 依赖的处理是"无条件拉取"，跟 build.zig 里引不引用它**没有任何关系**：

```zig
// lib/compiler/Maker/Fetch.zig
.lazy_status = switch (f.job_queue.mode) {
    .needed => if (dep.lazy) .available else .eager, // eager = 一定会去拉
    .all => .eager,
},
```

所以：`zon` 没写 `lazy = true` 时，Linux 上照样会下载 zigwin32。

### 2. 只要全局缓存里有那个 tarball，Zig 仍会往 `zig-pkg/` 复制一份

Zig 0.17 的 fetch 顺序是：先查 `zig-pkg/<hash>` → 再查全局缓存 `~/.cache/zig/p/<hash>.tar.gz`（命中就解包）→ **最后**才判断这个 lazy 依赖是否真的被需要：

```zig
// lib/compiler/Maker/Fetch.zig，注意两段的先后
if (job_queue.local_storage) |ls| { ... }            // 1. zig-pkg/<hash> 命中就直接用
if (cached_tarball_path...) |file| {                 // 2. 全局缓存命中 → 解包进 zig-pkg
    return f.runResource(cached_tarball_path, &resource, remote.hash, true);
}
switch (f.lazy_status) {                             // 3. 到这里才看 lazy / needed
    .available => if (!job_queue.unlazy_set.contains(expected_hash)) {
        f.lazy_status = .unavailable;
        return;
    },
    ...
}
```

这一步是**纯本地复制**（不联网、不参与编译），但目录确实会重新冒出来，很容易被误判成"又在拉库"。

## 正确用法

### a) `build.zig.zon`：给条件依赖标 lazy

```zig
.dependencies = .{
    // 只有 Windows 用得上
    .win32 = .{
        .url = "git+https://github.com/marlersoft/zigwin32#ec98bb4...",
        .hash = "win32-25.0.28-preview-mX5pFWMt5...",
        .lazy = true,
    },
    // Windows 默认 D3D11 也用不到（只有 -Dbackend=vulkan 才要）
    .vulkan = .{
        .url = "https://codeload.github.com/Snektron/vulkan-zig/tar.gz/1fa628...",
        .hash = "vulkan-0.0.0-r7Ytxy2BAwCPqBJUCXp6XXMwWqFD3DNrMLWWQvRRSXOC",
        .lazy = true,
    },
    // 每个平台都要用，保持 eager，少一轮配置
    .windowkit = .{ ... },
},
```

### b) `build.zig`：按目标分支解析，并且处理"还没拉取"

```zig
// 只在 Windows 分支里解析（非 Windows 根本不走到这里）
const d3d11_backend: ?*std.Build.Module = if (is_windows) blk: {
    const win32 = win32Module(b) orelse return;
    break :blk b.createModule(.{
        ...
        .imports = &.{
            .{ .name = "win32", .module = win32 },
            .{ .name = "render_types", .module = render_types },
        },
    });
} else null;

// 文件末尾：把"这个包可能还没拉取"收在一个函数里
fn win32Module(b: *std.Build) ?*std.Build.Module {
    const dep = b.lazyDependency("win32", .{}) orelse return null;
    return dep.module("win32");
}
```

要点：

- **`lazyDependency` 返回 `null` 不是错误**，含义是"这个包当前还没拉取"。调用它本身已经把需求登记进 `needed_lazy_dependencies`；此时 `orelse return` 结束本次配置，工具链拉完这个包后会**重跑一遍** `build.zig`，第二次就能拿到真正的 module。
- 首次在 Windows 上构建会多跑一轮配置（第一轮只登记需求 + 退出，第二轮真正建模块），这是 lazy 依赖的正常代价。
- **不要**写成"顶层解析成 `?*Module`、用到的地方 `win32.?`"：`.?` 是"我断言这里非空"的意思，而 Windows 首次配置时它恰好可能是 null（直接 panic）。把 `orelse return` 放在各自平台/后端的分支里，语义才对。
- `lazyDependency` 在 0.17 里标了 deprecated，推荐写法是 `dependencyLazy` 并把 `error.LazyDependencyNeeded` 一路上抛到 `build` 顶层；两者对"未拉取"的处理一致。非 lazy 的 `dependency()` 也能用（内部 `serializeConfigurationExiting` 直接退出并写出配置），但那是"配置中途退出"，语义不如显式判空清楚。
- 非 Windows 目标上**不要碰** `win32Module(b)`：引用了就会被标记 needed，然后就是一次真实网络拉取。
- `ShadeFlowNative/build.zig` 里同一套做法用在 `win32Module`（`is_windows`）/ `vulkanModule`（`use_vulkan`）两个函数上，调用点共 4 处。

## 怎么验证（本机没网也能判定）

只看 `zig-pkg` 里有没有目录是**判断不了**是否联网的（见根因 2）。可靠的对照实验：

```bash
# 1. 把全局缓存里的 tarball 挪走（模拟"从没拉过这个包"的机器）
mv ~/.cache/zig/p/win32-*.tar.gz /tmp/
# 2. 删掉 zig-pkg 里已有的目录
rm -rf zig-pkg/win32-*
# 3. 跑
zig build run
```

- 若它试图联网，本机没网会直接报 fetch 错误；exit 0 且目录不回来 = 真的没拉。
- 反过来把 tarball 放回缓存，再删目录跑一次，`zig-pkg/win32-...` 会重新出现（第 2 步的本地解包），但**不联网**。

实测记录（Zig 0.17.0，Linux）：

| 条件 | 结果 |
| --- | --- |
| 只加 `build.zig` 的 `if (is_windows)` 分支，zon 不标 lazy | 仍然拉取 —— 无效 |
| zon 标 `lazy = true` + `lazyDependency` + 全局缓存里没有 tarball | `zig build` 秒过、无目录、不联网 ✅ |
| zon 标 `lazy = true` + `lazyDependency` + 全局缓存里有 tarball | 目录又被本地解包出来（不联网、不编译） |
| Windows 交叉配置 `zig build -Dtarget=x86_64-windows-gnu -l` | 走 lazy 的 null → 拉取 → 重跑配置，正常带上 win32 ✅ |

## 结论与取舍

- 目标达成：mac / Linux 的 `zig build run` 不再为 win32 跑一次网络。
- 想连 `zig-pkg/win32-...` 都不出现，只能把全局缓存里那个 tarball 删掉（一次性）：`rm ~/.cache/zig/p/win32-*.tar.gz`。**本仓库已经删了**，所以现在 `zig-pkg` 里只有 vulkan 和 windowkit。代价是下次给 Windows 构建要重新下载（有网即可）。这是 Zig 0.17 fetch 顺序决定的，`build.zig` 控制不了。
- 需要提前给 Windows 备料、又不想天天被复制：`zig build --fetch=all` 会把包含 lazy 依赖在内的整棵依赖树拉下来（`--fetch[=needed|all]`）。
- `vulkan` 也标了 lazy：Windows 默认 D3D11 构建既不解析 vulkan-zig（`vendor/vk.xml` 生成 `vk.zig`），也不该去拉它。

## 代码位置

- `ShadeFlowNative/build.zig.zon` —— `win32` / `vulkan` 的 `.lazy = true`
- `ShadeFlowNative/build.zig` —— `win32Module` / `vulkanModule` 两个解析函数（文件末尾），调用点：`d3d11_backend`、`vulkan_backend` 的 Windows 导入、`capi` 模块、`typecheck-macos` 的 vulkan 绑定
- Zig 实现：`lib/compiler/Maker/Fetch.zig`（全局缓存分支在 lazy 判断之前）、`lib/compiler/Maker/Package/Manifest.zig`（`.lazy` 默认 false）、`lib/std/Build.zig` 的 `dependency` / `dependencyLazy` / `lazyDependency` / `serializeConfigurationExiting`
- 配置验证（Linux 主机上都能跑）：`zig build`、`zig build -Dtarget=x86_64-windows-gnu -l`、`zig build -Dtarget=x86_64-windows-gnu -Dbackend=vulkan -l`、`zig build typecheck-macos`
