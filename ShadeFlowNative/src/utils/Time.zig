const std = @import("std");

/// 帧计时器。时间单位统一为纳秒，跨平台走 `std.time.nanoTimestamp`
/// （Windows 上内部就是 QueryPerformanceCounter），不再直接依赖 win32。
pub const Time = struct {
    start_time: i64,
    last_frame_time: i64,
    delta_time: f64,
    total_time: f64,
    frame_count: u64,
    fps: f64,
    fps_update_time: f64,

    pub fn init() Time {
        const now = nanoTimestamp();
        return Time{
            .start_time = now,
            .last_frame_time = now,
            .delta_time = 0.0,
            .total_time = 0.0,
            .frame_count = 0,
            .fps = 0.0,
            .fps_update_time = 0.0,
        };
    }

    pub fn update(self: *Time) void {
        const now = nanoTimestamp();
        const ns_per_second: f64 = std.time.ns_per_s;

        // 计算 delta time
        self.delta_time = @as(f64, @floatFromInt(now - self.last_frame_time)) / ns_per_second;
        self.last_frame_time = now;

        // 更新总时间
        self.total_time = @as(f64, @floatFromInt(now - self.start_time)) / ns_per_second;

        // 更新帧率计算
        self.frame_count += 1;
        self.fps_update_time += self.delta_time;

        // 每秒更新一次帧率
        if (self.fps_update_time >= 1.0) {
            self.fps = @as(f64, @floatFromInt(self.frame_count)) / self.fps_update_time;
            self.frame_count = 0;
            self.fps_update_time = 0.0;
        }
    }

    pub fn getDeltaTime(self: *Time) f64 {
        return self.delta_time;
    }

    pub fn getTotalTime(self: *Time) f64 {
        return self.total_time;
    }

    pub fn getFPS(self: *Time) f64 {
        return self.fps;
    }

    fn nanoTimestamp() i64 {
        const io = std.Io.Threaded.global_single_threaded.io();
        return @intCast(std.Io.Clock.awake.now(io).nanoseconds);
    }
};
