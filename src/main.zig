const std = @import("std");

const Application = @import("engine/core/Application.zig").Application;

// 创建子类实现onCreate和onDestroy钩子
pub const MyApplication = struct {
    base: *Application,

    pub fn init(allocator: std.mem.Allocator) !*MyApplication {
        const app_ptr = try allocator.create(MyApplication);

        app_ptr.base = try Application.init(allocator);

        // 调用onCreate钩子
        try app_ptr.base.onCreate();

        return app_ptr;
    }

    pub fn deinit(self: *MyApplication) void {
        self.base.onDestroy();
        self.base.deinit();
    }

    pub fn run(self: *MyApplication) !void {
        try self.base.run();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try MyApplication.init(allocator);
    defer {
        app.deinit();
        allocator.destroy(app);
    }

    try app.run();
}
