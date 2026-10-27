//! D3D12 后端的错误辅助：记录上下文 + 原始 HRESULT，返回稳定的错误值。
//!
//! 统一收口：记录上下文 + 原始 HRESULT，返回稳定的 `error.HResultFailed`。

const std = @import("std");

const win32 = @import("win32").everything;

/// 检查 HRESULT，失败时记录「上下文 + HRESULT」并返回 `error.HResultFailed`。
pub fn check(hr: win32.HRESULT, comptime context: []const u8) error{HResultFailed}!void {
    if (hr == win32.S_OK) return;
    std.log.err("{s} 失败: HRESULT 0x{X}", .{ context, @as(u32, @bitCast(hr)) });
    return error.HResultFailed;
}
