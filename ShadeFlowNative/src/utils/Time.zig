const std = @import("std");

const win32 = @import("win32").everything;

pub const Time = struct {
    start_time: i64,
    last_frame_time: i64,
    delta_time: f64,
    total_time: f64,
    frame_count: u64,
    fps: f64,
    fps_update_time: f64,

    pub fn init() Time {
        var counter: win32.LARGE_INTEGER = undefined;
        _ = win32.QueryPerformanceCounter(&counter);
        return Time{
            .start_time = counter.QuadPart,
            .last_frame_time = counter.QuadPart,
            .delta_time = 0.0,
            .total_time = 0.0,
            .frame_count = 0,
            .fps = 0.0,
            .fps_update_time = 0.0,
        };
    }

    pub fn update(self: *Time) void {
        var current_time: win32.LARGE_INTEGER = undefined;
        _ = win32.QueryPerformanceCounter(&current_time);
        var frequency: win32.LARGE_INTEGER = undefined;
        _ = win32.QueryPerformanceFrequency(&frequency);

        // 计算delta time
        self.delta_time = @as(f64, @floatFromInt(current_time.QuadPart - self.last_frame_time)) / @as(f64, @floatFromInt(frequency.QuadPart));
        self.last_frame_time = current_time.QuadPart;

        // 更新总时间
        self.total_time = @as(f64, @floatFromInt(current_time.QuadPart - self.start_time)) / @as(f64, @floatFromInt(frequency.QuadPart));

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
};
