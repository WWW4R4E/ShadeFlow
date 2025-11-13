const std = @import("std");
const win32 = @import("win32").everything;
const L = win32.L;
pub const MainWindow = struct {
    hwnd: win32.HWND,

    const CLASS_NAME = L("ZigDx11WindowClass");

    fn wndProc(
        hwnd: win32.HWND,
        uMsg: u32,
        wParam: win32.WPARAM,
        lParam: win32.LPARAM,
    ) callconv(.winapi) win32.LRESULT {
        switch (uMsg) {
            win32.WM_DESTROY => {
                win32.PostQuitMessage(0);
                return 0;
            },
            else => return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam),
        }
    }

    pub fn init() !MainWindow {
        const wc = win32.WNDCLASSW{
            .style = .{},
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = win32.GetModuleHandleW(null),
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = CLASS_NAME,
        };

        if (win32.RegisterClassW(&wc) == 0)
            return error.FailedToRegisterClass;

        const hwnd = win32.CreateWindowExW(
            .{},
            CLASS_NAME,
            L("ZigWin32Window"),
            win32.WS_OVERLAPPEDWINDOW,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            800,
            600,
            null,
            null,
            wc.hInstance,
            null,
        ) orelse return error.FailedToCreateWindow;

        return .{ .hwnd = hwnd };
    }

    pub fn show(self: *MainWindow) void {
        _ = win32.ShowWindow(self.hwnd, win32.SW_SHOW);
        _ = win32.UpdateWindow(self.hwnd);
    }

    pub fn runMessageLoop() void {
        var msg: win32.MSG = undefined;
        while (win32.GetMessageW(&msg, null, 0, 0) > 0) {
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }
    }
};
