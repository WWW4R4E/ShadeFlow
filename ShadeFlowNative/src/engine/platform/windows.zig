//! Windows 宿主消息泵（Composition/DLL 模式）。

const win32 = @import("win32").everything;

/// 排空线程消息队列。返回 false 表示收到 `WM_QUIT`。
pub fn pumpMessages() bool {
    var msg: win32.MSG = undefined;
    while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);

        if (msg.message == win32.WM_QUIT) return false;
    }
    return true;
}
