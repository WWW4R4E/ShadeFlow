const std = @import("std");

/// 轴对齐包围盒（AABB）。
///
/// 这里只表示**物体局部空间**的范围：由顶点位置算出，不含 `Transform`。
/// 世界空间的范围按需用世界矩阵从局部盒派生，所以物体旋转时局部盒不用重建。
///
/// 退化盒（某个轴 `min == max`，例如 `Line` / `Rect` 的 z 厚度为 0）是合法的；
/// 没有顶点的空盒用 `EMPTY` 表示。
pub const Aabb = struct {
    min: [3]f32,
    max: [3]f32,

    /// 空盒：`min` 全为 +inf、`max` 全为 -inf，`expandPoint` 可以从它开始累积。
    pub const EMPTY = Aabb{
        .min = .{ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) },
        .max = .{ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) },
    };

    pub fn fromPoint(point: [3]f32) Aabb {
        return .{ .min = point, .max = point };
    }

    /// 把一个点纳入包围盒；在 `EMPTY` 上第一次调用即为初始化。
    pub fn expandPoint(self: *Aabb, point: [3]f32) void {
        for (0..3) |axis| {
            if (point[axis] < self.min[axis]) self.min[axis] = point[axis];
            if (point[axis] > self.max[axis]) self.max[axis] = point[axis];
        }
    }

    pub fn center(self: Aabb) [3]f32 {
        return .{
            (self.min[0] + self.max[0]) * 0.5,
            (self.min[1] + self.max[1]) * 0.5,
            (self.min[2] + self.max[2]) * 0.5,
        };
    }

    pub fn halfExtents(self: Aabb) [3]f32 {
        return .{
            (self.max[0] - self.min[0]) * 0.5,
            (self.max[1] - self.min[1]) * 0.5,
            (self.max[2] - self.min[2]) * 0.5,
        };
    }

    /// 空盒（从未加入过任何点）或 `min > max` 的非法盒返回 true。
    pub fn isEmpty(self: Aabb) bool {
        return self.min[0] > self.max[0] or
            self.min[1] > self.max[1] or
            self.min[2] > self.max[2];
    }
};

// =============================================================================
// 测试
// =============================================================================

test "空盒加入第一个点后就是那个点" {
    var bounds = Aabb.EMPTY;
    bounds.expandPoint(.{ 1.0, 2.0, 3.0 });

    try std.testing.expectEqual([3]f32{ 1.0, 2.0, 3.0 }, bounds.min);
    try std.testing.expectEqual([3]f32{ 1.0, 2.0, 3.0 }, bounds.max);
    try std.testing.expect(!bounds.isEmpty());
}

test "expandPoint 只向外扩，内部点不影响盒子" {
    var bounds = Aabb.fromPoint(.{ 0.0, 0.0, 0.0 });
    bounds.expandPoint(.{ -1.0, 0.5, 2.0 });
    // 严格在盒子内部：min = (-1, 0, 0)，max = (0, 0.5, 2)
    bounds.expandPoint(.{ -0.5, 0.1, 0.1 });

    try std.testing.expectEqual([3]f32{ -1.0, 0.0, 0.0 }, bounds.min);
    try std.testing.expectEqual([3]f32{ 0.0, 0.5, 2.0 }, bounds.max);
}

test "EMPTY 是空盒" {
    try std.testing.expect(Aabb.EMPTY.isEmpty());
}

test "退化盒（某个轴 min == max）是合法的，不算空" {
    // Line / Rect 这类几何体在某个轴上厚度为 0
    const flat = Aabb{ .min = .{ -1.0, -1.0, 0.0 }, .max = .{ 1.0, 1.0, 0.0 } };
    try std.testing.expect(!flat.isEmpty());
}

test "center 与 halfExtents" {
    const bounds = Aabb{ .min = .{ -1.0, -2.0, -3.0 }, .max = .{ 1.0, 2.0, 3.0 } };

    try std.testing.expectEqual([3]f32{ 0.0, 0.0, 0.0 }, bounds.center());
    try std.testing.expectEqual([3]f32{ 1.0, 2.0, 3.0 }, bounds.halfExtents());
}
