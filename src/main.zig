const std = @import("std");
const window = @import("window.zig");

pub fn main() !void {
    var win = try window.MainWindow.init();
    win.show();
    window.MainWindow.runMessageLoop();
}
