const std = @import("std");

const win32 = @import("win32");

const Engine = @import("engine/core/Engine.zig").Engine;
const Window = @import("engine/core/Window.zig").Window;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var Mainwindow = try Window.init(allocator);
    Mainwindow.show();

    const size = Mainwindow.getClientSize();

    var app = try Engine.init(allocator, size.width, size.height, Mainwindow.hwnd);

    try app.run();
    defer app.deinit();
}
