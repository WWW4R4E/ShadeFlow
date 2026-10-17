//! 非 Windows 平台：没有 Win32 消息队列可泵。
//!
//! Linux 的窗口/输入事件由 windowkit 的 Wayland 事件循环负责；走到这里说明
//! 引擎处于「无窗口、外部驱动」模式，直接视为继续运行。

pub fn pumpMessages() bool {
    return true;
}
