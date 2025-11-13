const std = @import("std");

const win32 = @import("win32").everything;

pub const Time = struct {
    start_time: u64,
    last_frame_time: u64,
    delta_time: f64,
    total_time: f64,
    frame_count: u64,
    fps: f64,
    fps_update_time: f64,

    pub fn init() Time {
        return Time{
            .start_time = win32.GetPerformanceCounter(),
            .last_frame_time = win32.GetPerformanceCounter(),
            .delta_time = 0.0,
            .total_time = 0.0,
            .frame_count = 0,
            .fps = 0.0,
            .fps_update_time = 0.0,
        };
    }

    pub fn update(self: *Time) void {
        const current_time = win32.GetPerformanceCounter();
        const frequency = win32.GetPerformanceFrequency();

        // 计算delta time
        self.delta_time = @as(f64, @floatFromInt(current_time - self.last_frame_time)) / @as(f64, @floatFromInt(frequency));
        self.last_frame_time = current_time;

        // 更新总时间
        self.total_time = @as(f64, @floatFromInt(current_time - self.start_time)) / @as(f64, @floatFromInt(frequency));

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
