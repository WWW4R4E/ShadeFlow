//! Vulkan 后端的错误辅助。
//!
//! vulkan-zig 的 wrapper 已经把绝大多数 `VkResult` 翻译成 Zig error；
//! 这里只处理少数仍直接返回 `Result` 的调用（如 acquire/present），
//! 并统一日志格式。

const std = @import("std");

const vk = @import("vulkan");

pub fn check(result: vk.Result, comptime context: []const u8) error{VulkanFailure}!void {
    if (result == .success) return;
    std.log.err("{s} 失败: {s}", .{ context, @tagName(result) });
    return error.VulkanFailure;
}
