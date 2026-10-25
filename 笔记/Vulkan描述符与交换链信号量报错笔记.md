# Vulkan 描述符与交换链信号量报错笔记

> 记录一次 `zig build run`（Vulkan 后端）里同时爆出的两条 validation 错误：一条是 descriptor 的
> `VK_WHOLE_SIZE` + dynamic offset 契约写错，另一条是 present 信号量被提前复用。
>
> 状态：**只做了分析，代码未改**。下面的修法是待执行的方案，不是已完成的事实。
> 相关代码：`ShadeFlowNative/src/engine/render/backend/vulkan/`

## 现象

窗口缩放后，validation 层连续报两类错：

```
info: 窗口尺寸变化：逻辑 829x986，物理 1658x1972（scale 2.00）
info: Vulkan 交换链：1658x1972，5 张图像，present 模式 fifo_khr

error: [vulkan] vkCmdBindDescriptorSets(): pDynamicOffsets[0] is 224, but must be zero
since the buffer descriptor's range is VK_WHOLE_SIZE in descriptorSet #0 binding #0
descriptor[0].
（VUID-vkCmdBindDescriptorSets-pDescriptorSets-06715）

error: [vulkan] vkQueueSubmit(): pSubmits[0].pSignalSemaphores[0] (VkSemaphore 0x…01c) is
being signaled by VkQueue …, but it may still be in use by VkSwapchainKHR 0x…03e.
Swapchain image 0 was presented but was not re-acquired …
（VUID-vkQueueSubmit-pSignalSemaphores-00067）
```

两条错误的性质完全不同，**不要一起改**：

| # | 报错函数 | 性质 | 改动量级 |
|---|---|---|---|
| 1 | `vkCmdBindDescriptorSets` | API 契约写错（参数/数值） | 改 `VkDescriptorBufferInfo::range` 一处 |
| 2 | `vkQueueSubmit` | 资源生命周期 / 同步不变量被破坏（结构） | 改 `Sync` 的数组长度 + 索引方式，外加几条边界路径 |

---

# 一、`VK_WHOLE_SIZE` + 非 0 dynamic offset

## 1. 规范判据

> 若 descriptor 的 `range` 是 `VK_WHOLE_SIZE`，那么绑定时对应的 dynamic offset **必须是 0**。
> —— VUID `vkCmdBindDescriptorSets-pDescriptorSets-06715`

## 2. 为什么规范要这么规定

descriptor 实际暴露给着色器的区间是“拼”出来的：

```
起点 = VkDescriptorBufferInfo::offset + pDynamicOffsets[i]
长度 = VkDescriptorBufferInfo::range
```

而 `VK_WHOLE_SIZE` 的含义是“从 `offset` 一直到 buffer 末尾”，**长度依赖 buffer 大小**，不是常量。
再叠加 dynamic offset 之后，语义变成“从 `offset + dynamicOffset` 到 buffer 尾”，长度随槽位变化，
规范干脆禁止：`VK_WHOLE_SIZE` 只允许 dynamic offset 为 0。

## 3. 代码定位

`Descriptor.zig`，建 descriptor set 的地方：

```zig
// Descriptor.zig:194
const buffer_info = [_]vk.DescriptorBufferInfo{
    .{ .buffer = frame.buffer.handle, .offset = 0, .range = vk.WHOLE_SIZE },  // ← 问题在这
};
```

`Renderer.zig`，每次 draw 绑定时传槽位偏移：

```zig
// Renderer.zig:385
const sets = [_]vk.DescriptorSet{descriptor.currentSet(self.frame_index % frames_in_flight)};
const dynamic_offsets = [_]u32{@intCast(self.constants_offset)};   // ← 槽位偏移，非 0
w.cmdBindDescriptorSets(cmd, .graphics, descriptor.pipeline_layout, 0, &sets, &dynamic_offsets);
```

`constants_offset` 来自 `Descriptor.writeConstants`：`offset = used_slots * slot_size`，第二个 draw 就是 224。

## 4. 这个设计本身是对的

整帧的常量塞进一块 host-visible buffer，按 `minUniformBufferOffsetAlignment` 切槽，draw 之间只换
dynamic offset —— 这是标准做法（见 `Descriptor.zig` 顶部注释）。**错的只有 `range` 一个字段。**

这也是为什么它会“看起来能跑”：很多驱动按 `offset + range` 截取，不校验这个组合，只是读到的位置
不对，表现为所有物体共用同一份变换（后一个对象覆盖前一个）。

## 5. 修法：把 range 写成显式长度

```zig
// Descriptor.zig:194
.range = self.slot_size,   // 不用 vk.WHOLE_SIZE
```

`createPoolAndFrames` 里 `self.slot_size` 在 `updateDescriptorSets` 之前已经赋值，可直接用。
若要更保守，用 `alignForward(data.len, alignment)`，数值等于 `slot_size`。

### 修完必须自查的四条约束

1. `descriptor.offset + range <= buffer.size`：`0 + slot_size <= slot_size * capacity_slots` ✔
2. **`dynamicOffset + range <= buffer.size`**：最后一槽 `(capacity-1)*slot_size + slot_size` 正好等于
   buffer 尾 ✔ —— 这也说明 `buffer_size = slot_size * capacity_slots` 这个写法不能少一个字节，
   否则“最后一个物体的常量”越界。
3. `dynamicOffset % minUniformBufferOffsetAlignment == 0`：已满足，因为
   `slot_size = alignForward(data.len, alignment)`，offset 恒为 `n * slot_size`。
4. `range <= maxUniformBufferRange`（常见 64 KiB）：224/256 远小于上限；但常量结构变大时要加断言。

另外：`range` 必须**不小于着色器实际读的字节数**（`Engine.Constants` 是 224 字节，
`3 * 64 + 2 * 16`），`slot_size >= 224` 已满足。

## 6. 顺带解释日志里的 224

224 = `sizeof(Constants)`，说明这台设备报告的 `minUniformBufferOffsetAlignment` 能整除 224
（AMD 常见 4；NVIDIA 是 256，那时槽位偏移会是 256/512）。

结论：
- **不要**把对齐写死成 256；`Device.minUniformBufferOffsetAlignment()` 已按规范查询。
- **不要**因为看到 224 就以为对齐算错了。想确认就临时打一行日志：
  `std.log.info("uniform alignment = {d}", .{alignment})`。

## 7. 怎么验证修好了

- validation 对该条完全静默；
- 场景里两个以上物体的变换各不相同（否则说明 offset/range 仍然错，只是没触发校验）；
- 反向实验：把 `range` 改成 `slot_size + 1`，应出现“range 越界”类报错 —— 能复现，才算真懂了这条判据。

---

# 二、present 信号量被提前复用

## 1. 报错在读什么

```
VkSemaphore 0x…01c is being signaled by VkQueue, but it may still be in use by VkSwapchainKHR 0x…03e.
Most recently acquired image indices: [0], 1, 2.
(Brackets mark the last use of VkSemaphore … in a presentation operation.)
Swapchain image 0 was presented but was not re-acquired …
```

一句话：**要 signal 的这个 binary semaphore，上一次被 `vkQueuePresentKHR` 当 wait semaphore 用，
而那次 present 还没有确定结束。**

## 2. 根因：fence 保证不到 present

`Sync.zig` 的组织方式：

```zig
image_available: [frames_in_flight]vk.Semaphore,   // 按帧槽
render_finished: [frames_in_flight]vk.Semaphore,   // 按帧槽  ← 问题
in_flight:       [frames_in_flight]vk.Fence,
image_in_flight: []vk.Fence,                       // 按图像
```

`beginFrame` 先 `waitFrame(frame)`，然后复用 `render_finished[frame]`。但：

- `in_flight[frame]` 这个 fence **只覆盖 `vkQueueSubmit` 提交的工作**；
- present 的 wait 在**展示引擎（presentation engine）**里完成，它不是 queue 提交的工作，
  任何 fence 都不会因为它触发；
- 所以 “fence 触发了” ≠ “上一次 present 已经消费掉 `render_finished[frame]`”。

`Sync.zig` 顶部注释其实已经写了 present 信号量“表示这一帧确实画完了”，但没写“**它什么时候可以被再次 signal**”。

## 3. 为什么在这个场景必然触发

- 帧槽 `frames_in_flight = 2`，交换链图像 5 张（日志：`5 张图像`）；
- 帧槽每 2 帧循环一次，而图像回收要等 FIFO 队列走到第 5 张 —— **帧槽复用周期短于图像回收周期**，
  所以这个复用必然撞上，只是什么时候被 validation 抓到；
- 窗口 resize / 重建交换链会让它更容易稳定复现（`deviceWaitIdle` 也不覆盖 present）。

## 4. 正确的不变量

> binary semaphore 只有在“它上一次的 wait **已被证明执行完**”之后，才能再次 signal。

对 present 信号量，无扩展 Vulkan 只有一个可靠证明方式：

> **再次 acquire 到同一张图像，并在这次 submit 里 wait 它的 acquire 信号量。**

这保证“上一次使用该图像的 present 已经结束”，从而保证那次 present 对 `render_finished` 的 wait 已经发生。
（Khronos Guide 的原话：acquire 之后**在 submit 里等掉** acquire 信号量，才能说对应的信号量可以复用。）

### 索引原则：谁 wait 它，就按谁的周期分配

| 信号量 | 数量 | signal 方 | wait 方 | 何时可安全复用 |
|---|---|---|---|---|
| `image_available[frame]` | `frames_in_flight` | `vkAcquireNextImageKHR` | 本帧 `vkQueueSubmit` | 该帧 fence 触发（wait 已消费） |
| `render_finished[image]` | **交换链图像数** | 本帧 `vkQueueSubmit` | `vkQueuePresentKHR` | 重新 acquire 到该 image，并在 submit 中 wait 掉 acquire 信号量之后 |

`image_in_flight[image]` 那套 per-image fence 建议保留：它保护的是“往这张图像写”，语义清楚、
成本可忽略（严格说它在 acquire 之后已是冗余，但留着更直观）。

## 5. 修法 A：per-image present 信号量（改动最小）

核心两处：

```zig
// Sync.zig —— 长度跟着交换链走
render_finished: []vk.Semaphore = &.{},

// Renderer.endFrameInner —— 用 image_index，而不是 frame
const present_semaphore = [_]vk.Semaphore{self.sync.render_finished[self.image_index]};
```

`image_available` / `in_flight` 保持按 `frame`，因为它们的消费者是 submit / fence。

### 光改这两行不够：必须一起处理的边界情况

**(a) acquire 成功但这一帧没提交。**
`beginFrameInner` 里 `acquire` 之后若 `beginCommandBuffer` / `cmdBeginRenderPass` 失败，
`frame_active` 仍为 false，`endFrame` 直接 return，acquire 信号量悬在 signaled 状态。下一轮再拿它
acquire，违反的是 `VUID-vkAcquireNextImageKHR-semaphore-01286`。要么补一个空 submit 消费掉，
要么统一走“重建交换链 + 重建信号量”的兜底。

**(b) present 返回 `OUT_OF_DATE_KHR`。**
规范不保证这种情况下的 wait 被执行过。现在代码是直接 `recreateSwapChain()` 继续跑，信号量状态
“未知”。安全做法：`deviceWaitIdle` → 重建 swapchain → **销毁并重建 present 信号量**（不要沿用）。

**(c) `deviceWaitIdle` 不覆盖 present。**
WaitIdle 是按 fence 定义的，而 `vkQueuePresentKHR` 没有 fence 参数。所以“重建时 `deviceWaitIdle`
一下再销毁信号量”严格说是近似 —— 业界普遍这么做，未启用 maintenance1 时 validation 也不报。
知道这是近似即可。

**(d) 交换链重建时图像数会变。**
`Sync.resizeImageFences` 已按新 `imageCount()` 重建 fence 数组，`render_finished` 要一起重建
（销毁旧的，别只 realloc 复用句柄）。可以考虑把两者合并成
`resizeSwapchainResources(image_count)`。

**(e) 退出路径。**
`Sync.deinit` 销毁信号量前也走同样的兜底，避免 present 未完成时销毁。

## 6. 修法 B：`VK_KHR_swapchain_maintenance1`（更彻底，非必需）

- 在 `VkPresentInfoKHR::pNext` 挂 `VkSwapchainPresentFenceInfoEXT`，给每次 present 一个 fence；
- present 真正完成时 fence 触发，于是可以按帧槽复用 `render_finished`，用 `vkWaitForFences` 判断；
- 顺带解决 (b)(c)(e) 全部“状态未知”。

代价：`Device.zig` 请求扩展、`SwapChain` 挂 pNext、`Sync` 多一组 present fence。属于第二阶段优化。

## 7. 怎么验证修好了

- `VUID-vkQueueSubmit-pSignalSemaphores-00067` 消失；
- 打开 **sync validation**（`VK_LAYER_KHRONOS_validation` 的同步校验子特性 / vkconfig 里
  “Synchronization Validation”），它会把 hazard 定位到具体 semaphore 与两次操作；
- 高频 resize（拖窗口边缘）+ 快速切前后台，跑几分钟；
- 注意错误是**异步**的：报错发生在下一帧 `vkQueueSubmit`，要对照“上一帧用的哪个槽/哪张图像”。

## 8. 调试技巧：把句柄映射回槽位

validation 报的是**句柄值**（`0x1c000000001c`）。在创建时打一行日志：

```zig
std.log.info("render_finished[{d}] = 0x{x}", .{ i, semaphore });
```

就能直接把报错句柄映射回槽位，比猜快得多。

---

# 三、以后遇到同类报错的通用套路（30 秒判断法）

1. **看报错的函数名**
   - `vkCmdBindDescriptorSets` / `vkCmdBindVertexBuffers` 之类 → 参数/契约问题，读 VUID 即可；
   - `vkQueueSubmit` / `vkQueuePresentKHR` / `vkAcquireNextImageKHR` → 生命周期/时序问题，要画时间线。
2. **抄 VUID 去规范里搜那一段 “Each … must …”**，那才是判据原文，报错里的英文只是复述。
3. **在代码里找到“产生这个句柄 / 这个绑定”的那一处**，把生命周期画成时间线：
   谁创建、谁 signal、谁 wait、跨了几帧、什么时候销毁。
4. **问一句：“我用来判断可复用的那个信号，能证明这件事发生了吗？”**
   - 错误 1 的答案：“能，但我把 range 填错了”；
   - 错误 2 的答案：“不能，fence 不覆盖 present”。
   所有同步类 bug 都卡在这一问。
5. **先用最小实验验证判据**（故意把 range 改小、故意复用信号量），确认能复现，再改正式代码。

---

# 四、学习路径：这些知识在 vulkan-tutorial.com 的哪一章

结论：**tutorial 到 #17 结束，足以写出当前这份代码，也足以写出这两个 bug。** 它教的是“画面能出来”，
不是“合规”。跨越这一步靠两篇 Khronos Guide。

| 序 | 材料 | 读它的目的 |
|---|---|---|
| 1 | [tutorial #15 Rendering and Presentation](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Rendering_and_presentation) | semaphore vs fence、谁能观测谁的完成 —— 两条错误都靠这张表 |
| 2 | [tutorial #16 Frames in Flight](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Frames_in_flight) | 理解为什么要 per-frame 复制；**同时知道这里的示例代码本身是反例** |
| 3 | [Khronos Guide: Swapchain Semaphore Reuse](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html) | 拿到正确不变量：present 信号量按图像索引 |
| 4 | [tutorial #17 Swap Chain Recreation](https://vulkan-tutorial.com/Drawing_a_triangle/Swap_chain_recreation) | 学“复位时机必须绑定到必定发生的那次提交”这种推理方式 |
| 5 | [tutorial #22 Descriptor Set Layout and Buffer](https://vulkan-tutorial.com/Uniform_buffers/Descriptor_set_layout_and_buffer) | 建立 offset / range / 每帧 buffer 的概念 |
| 6 | [tutorial #23 Descriptor Pool and Sets](https://vulkan-tutorial.com/Uniform_buffers/Descriptor_pool_and_sets) | `range = sizeof(UBO)` 的写法，以及 `WHOLE_SIZE` 的诱惑从哪来 |
| 7 | [Khronos Guide: Descriptor Dynamic Offset](https://docs.vulkan.org/guide/latest/descriptor_dynamic_offset.html) | 补上 tutorial 缺的那章：dynamic offset 与 WHOLE_SIZE 互斥 |
| 8 | [规范：Descriptor Sets](https://docs.vulkan.org/spec/latest/chapters/descriptorsets.html) | dynamic offsets 小节 + `minUniformBufferOffsetAlignment` / `maxUniformBufferRange` |

## 4.1 错误一在 tutorial 里的映射

- **#22**：给出 `VkDescriptorBufferInfo` 的 offset/range 模型，以及“每帧一份 UBO”的做法。
- **#23**：给出 `range = sizeof(UniformBufferObject)`，紧接着一句：
  *“If you're overwriting the whole buffer … it is also possible to use `VK_WHOLE_SIZE`.”*
  这句在“buffer 里只有一份 UBO”时成立；一旦变成“一帧 N 个槽位的环”，范围就不是“到 buffer 尾”，
  而是“一个槽”，照抄就踩雷。
- 同一章还有关键伏笔：`vkCmdBindDescriptorSets(..., 0, nullptr)` 后面写着
  *“The last two parameters specify an array of offsets that are used for dynamic descriptors.
  We'll look at these in a future chapter.”*
  —— **那个 future chapter 不存在**。Uniform Buffers 只有 #22/#23 两章。

所以以下内容 tutorial 完全没讲，必须靠 Guide / 规范补：

- `VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC`（layout、pool 怎么配）；
- `dynamicOffsetCount / pDynamicOffsets`；
- `minUniformBufferOffsetAlignment`（为什么 offset 是 224 而不是 256）、`maxUniformBufferRange`；
- “offset + dynamicOffset + range 必须落在 buffer 内”。

补充对照：tutorial 的做法（**每帧一个独立 UBO + 一个独立 descriptor set**）其实是“绕开 dynamic
offset”的合法方案，能成立是因为一份常量只服务一次 draw。一旦要“多个物体多份变换”，要么走
tutorial 的路线（N 个 buffer + N 个 set，draw 前换 set），要么走 ring buffer + dynamic offset。
理解这一点，就知道当初为什么选后者。

## 4.2 错误二在 tutorial 里的映射

- **#15** 把 semaphore 语义讲清楚了，而且有一句就是所有复用类 bug 的判据来源：
  *“After operation B **begins executing**, semaphore S is automatically reset back to being
  unsignaled, allowing it to be used again.”*
  注意 “begins executing” 指的是**队列操作开始执行**；present 的 wait 由展示引擎执行，
  不是可观测的队列操作 —— 这正是报错的技术核心。
- **#15 结尾的彩蛋**：关窗口时 validation 报 “semaphore in use”，原因是退出时 present 可能还在进行。
  和第二个错误是同一类问题（present 生命周期不可观测），当时用 `vkDeviceWaitIdle` 糊过去了。
- **#16** 的错误示例（和本项目的写法同源）：

  ```cpp
  std::vector<VkSemaphore> renderFinishedSemaphores;   // 按帧 ← 问题
  VkSemaphore signalSemaphores[] = {renderFinishedSemaphores[currentFrame]};
  presentInfo.pWaitSemaphores = signalSemaphores;      // present 等它
  ```

  从 validation 1.4.313 起，这段代码会直接报 `VUID-vkQueueSubmit-pSignalSemaphores-00067`。
  **不是“没学会”，是教程这里写错了。**
- #16 结尾其实给了一条逃生通道（容易被忽略）：链接到 Khronos 的
  [Synchronization Examples · swapchain image acquire and present](https://github.com/KhronosGroup/Vulkan-Docs/wiki/Synchronization-Examples#swapchain-image-acquire-and-present)，
  那里才是正确时序；后来 Khronos 又写了更专门的 *Swapchain Semaphore Reuse*。
- **#17** 里有两处同构的推理，值得当思维训练：
  - deadlock 那节：fence 被 reset 了但这帧因 `OUT_OF_DATE` 提前 return，没人 signal → 永久阻塞。
    结论是“**复位动作必须绑定到一定会被 signal 的那次提交**”。
  - resize 那节：`recreateSwapChain` 里 `vkDeviceWaitIdle`，并要求重建放在 present 之后做，
    “否则 semaphore 状态会不一致”。
  - 但 tutorial 不会告诉你“所以 present 用的 semaphore 要按图像索引，而不是按帧索引”，
    因为它的示例本身就是错的。

## 4.3 tutorial 的三个已知坑（本文两条错误都踩中了两个）

1. **#16** 的 per-frame `renderFinishedSemaphores` 是违反规范的反例。
2. **#23** 的 `VK_WHOLE_SIZE` 建议只在“descriptor 覆盖整块 buffer 且没有 dynamic offset”时成立。
3. **#23** 承诺的 “future chapter”（dynamic offsets）从未出现。

---

# 五、用 tutorial 做最小验证实验（推荐）

想亲眼看到因果，而不是靠记忆：

1. **信号量**：把 #16 的 `renderFinishedSemaphores` 改成按 `swapChainImages.size()` 分配、
   用 `imageIndex` 索引，其余不动 → 报错消失。差别只是“数组长度 + 一个下标”。
2. **descriptor**：把 #23 的 `range` 改成 `VK_WHOLE_SIZE`，descriptor type 改成
   `UNIFORM_BUFFER_DYNAMIC`，bind 时传一个非 0 offset → 复现第一条报错。
3. 再把 `range` 改回 `sizeof(...)`，offset 继续传 → 正常。这样“报错 ↔ 一个字段”就对上了。

本项目内的等价实验：把 `Descriptor.zig` 的 `range` 临时改成 `slot_size + 1`，
观察 range 越界类报错，理解 `dynamicOffset + range` 的边界。

---

# 六、修复顺序与待办

1. **先改 `Descriptor.zig` 的 `range`**（独立、低风险）→ 跑一轮确认第一条报错消失、多物体变换正确。
2. **再改 `Sync` / `Renderer` 的 present 信号量索引**，同时把边界情况 (a)(b)(d)(e) 写进代码注释：
   这三条是这次真正学到的东西，比改动本身值钱。
3. `maintenance1` + present fence 留作后续，别和 bug 修复混在一个提交里。
4. 每个改动都用 `zig build run` + 拖窗口验证；Windows / Linux / macOS 各跑一次
   （MoltenVK 对 semaphore 复用比桌面驱动更容易直接出问题）。

## 自查清单

- [ ] `range != VK_WHOLE_SIZE`，且 `range <= maxUniformBufferRange`
- [ ] `dynamicOffset + range <= buffer.size`（最后一槽正好贴尾）
- [ ] `dynamicOffset % minUniformBufferOffsetAlignment == 0`
- [ ] `render_finished` 长度 = 交换链图像数，索引用 `image_index`
- [ ] acquire 成功但跳帧的路径不会留下已 signal 的 acquire 信号量
- [ ] present 返回 `OUT_OF_DATE` 时重建 swapchain 并重建信号量
- [ ] 重建时 `render_finished` 数组跟着 `imageCount()` 一起重分配
- [ ] 退出路径有 `deviceWaitIdle` 兜底（知道它不覆盖 present）

---

# 七、术语速查

| 术语 | 本文中的含义 |
|---|---|
| descriptor | 着色器访问资源的“指针”，`VkDescriptorBufferInfo` 描述 buffer 的一段 |
| dynamic offset | 绑定时才给出的额外偏移，让一个 descriptor 服务多个槽位 |
| binary semaphore | 两个状态（signaled / unsignaled），wait 消费后自动复位，不能重复 signal |
| fence | CPU 侧等待用；只能观测 `vkQueueSubmit` 的完成，**不能**观测 present |
| present 信号量 | `VkPresentInfoKHR::pWaitSemaphores`，由提交 signal、展示引擎 wait |
| `frames_in_flight` | 同时在飞的帧数（本项目 2）；决定 command buffer / fence / acquire 信号量的数量 |
