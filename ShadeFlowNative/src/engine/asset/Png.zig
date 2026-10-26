//! PNG（及其他 zigimg 支持的格式）解码包装：统一转成 RGBA8 像素。
//!
//! 本轮只到 CPU 像素（`load` → `ImageData`），上传 GPU 与采样在渲染侧的
//! 纹理支持落地后接入。zigimg 支持的 JPEG/BMP 等格式顺带免费获得。

const std = @import("std");
const zigimg = @import("zigimg");

pub const ImageData = struct {
    width: u32,
    height: u32,
    /// RGBA8，每像素 4 字节，行优先。
    pixels: []u8,

    pub fn deinit(self: *ImageData, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.pixels = &.{};
    }
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !ImageData {
    const io = std.Io.Threaded.global_single_threaded.io();
    var read_buffer: [8192]u8 = undefined;
    var image = try zigimg.Image.fromFilePath(allocator, io, path, &read_buffer);
    defer image.deinit(allocator);
    return toRgba8(allocator, &image);
}

pub fn loadFromMemory(allocator: std.mem.Allocator, bytes: []const u8) !ImageData {
    var image = try zigimg.Image.fromMemory(allocator, bytes);
    defer image.deinit(allocator);
    return toRgba8(allocator, &image);
}

fn toRgba8(allocator: std.mem.Allocator, image: *zigimg.Image) !ImageData {
    // convert 失败时像素所有权仍在调用方的 defer 里；成功后同一份存储换成
    // rgba32，同样由调用方的 defer 释放，这里只做拷贝。
    try image.convert(allocator, .rgba32);

    const bytes = try allocator.dupe(u8, image.rawBytes());
    return .{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .pixels = bytes,
    };
}

// =============================================================================
// 测试：用 zigimg 自己的编码器生成 PNG 再解码回来（不需要提交二进制 fixture）
// =============================================================================

const testing = std.testing;

test "PNG 编解码往返：尺寸与像素保真" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 造一张 3x2 的 RGBA 渐变图。
    var source = try zigimg.Image.create(allocator, 3, 2, .rgba32);
    defer source.deinit(allocator);
    for (0..6) |i| {
        source.pixels.rgba32[i] = .{
            .r = @intCast(i * 40 % 256),
            .g = @intCast(i * 80 % 256),
            .b = @intCast(i * 120 % 256),
            .a = 255,
        };
    }

    // writeToMemory 的 write_buffer 是编码期的 scratch，PNG 用不了多大，
    // 给 64KB 富余。
    const scratch = try allocator.alloc(u8, 64 * 1024);
    const encoded = try source.writeToMemory(allocator, scratch, .{ .png = .{} });

    var decoded = try loadFromMemory(allocator, encoded);
    defer decoded.deinit(allocator);

    try testing.expectEqual(@as(u32, 3), decoded.width);
    try testing.expectEqual(@as(u32, 2), decoded.height);
    try testing.expectEqualSlices(u8, source.rawBytes(), decoded.pixels);
}
