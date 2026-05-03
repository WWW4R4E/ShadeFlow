const std = @import("std");

const win32 = @import("win32").everything;

pub const HResultError = struct {
    hr: win32.HRESULT,

    pub fn init(self: *HResultError, hr: win32.HRESULT) void {
        self.hr = hr;
        std.log.err("HRESULT Error: 0x{X}", .{@as(u32, @bitCast(hr))});
    }
};
