const std = @import("std");
const Camera = @import("Camera.zig").Camera;
const Object = @import("../scene/Object.zig").Object;
const Matrix = @import("../../utils/math/Matrix.zig").Matrix;
const Aabb = @import("../../utils/math/Aabb.zig").Aabb;

/// 方向分量小于这个值就当作 0：直接做 1/0 会得到 inf，
/// 再乘上恰好为 0 的 `min - origin` 会变成 NaN。
const DIRECTION_EPSILON: f32 = 1e-8;

pub const Viewport = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    pub fn aspectRatio(self: Viewport) f32 {
        return self.width / self.height;
    }

    pub fn screenToNDC(self: Viewport, screen_x: f32, screen_y: f32) struct { x: f32, y: f32 } {
        return .{
            .x = (2.0 * (screen_x - self.x)) / self.width - 1.0,
            .y = 1.0 - (2.0 * (screen_y - self.y)) / self.height,
        };
    }
};

/// 射线与 AABB 相交的参数区间。
/// 方向向量归一化时，`enter` / `exit` 就是到射线起点的距离。
pub const RayInterval = struct {
    enter: f32,
    exit: f32,
};

pub const Ray = struct {
    origin: [3]f32,
    direction: [3]f32,

    pub fn init(origin: [3]f32, direction: [3]f32) Ray {
        return Ray{
            .origin = origin,
            .direction = direction,
        };
    }

    pub fn at(self: Ray, distance: f32) [3]f32 {
        return .{
            self.origin[0] + self.direction[0] * distance,
            self.origin[1] + self.direction[1] * distance,
            self.origin[2] + self.direction[2] * distance,
        };
    }

    /// 射线与 AABB 的 slab 测试，返回进入/离开参数；没有交集返回 null。
    ///
    /// 方向不需要归一化，所以可以直接用于局部空间里被缩放过的射线。
    pub fn intersectsAabb(self: Ray, bounds: Aabb) ?RayInterval {
        if (bounds.isEmpty()) return null;

        var enter: f32 = -std.math.inf(f32);
        var exit: f32 = std.math.inf(f32);

        for (0..3) |axis| {
            const origin = self.origin[axis];
            const direction = self.direction[axis];
            const min = bounds.min[axis];
            const max = bounds.max[axis];

            // 方向分量为 0 时这一轴不限制参数区间，只要求原点落在范围内。
            // 退化轴（min == max，例如 Line 的 z）也走这条分支。
            if (@abs(direction) < DIRECTION_EPSILON) {
                if (origin < min or origin > max) return null;
                continue;
            }

            const inverse_direction = 1.0 / direction;
            var near = (min - origin) * inverse_direction;
            var far = (max - origin) * inverse_direction;
            if (near > far) {
                const swap = near;
                near = far;
                far = swap;
            }

            if (near > enter) enter = near;
            if (far < exit) exit = far;
            if (enter > exit) return null;
        }

        return .{ .enter = enter, .exit = exit };
    }
};

/// 拾取结果。`distance` 是沿射线的世界空间距离，`point` 是命中点。
pub const PickResult = struct {
    object: *Object,
    distance: f32,
    point: [3]f32,
};

pub const Picker = struct {
    /// 屏幕坐标（物理客户区像素）拾取最近的物体。
    pub fn pick(
        screen_x: f32,
        screen_y: f32,
        viewport: *const Viewport,
        camera: *const Camera,
        objects: []*Object,
    ) ?PickResult {
        const ray = rayFromScreen(screen_x, screen_y, viewport, camera);
        return pickRay(ray, camera, objects);
    }

    /// 用已有的世界空间射线拾取，方便 hover 之类的场景直接复用。
    pub fn pickRay(ray: Ray, camera: *const Camera, objects: []*Object) ?PickResult {
        var closest: ?PickResult = null;

        for (objects) |object| {
            const world_matrix = object.transform.getWorldMatrix();
            const inverse_matrix = Matrix.invertAffine(world_matrix) orelse continue;

            // 把射线搬到物体局部空间，直接用局部 AABB 判定：
            // 旋转、缩放都能精确处理，也不用每帧重建世界包围盒。
            const local_origin = Matrix.transformPoint(inverse_matrix, ray.origin);
            const local_direction = Matrix.transformDirection(inverse_matrix, ray.direction);

            const interval = Ray.init(local_origin, local_direction)
                .intersectsAabb(object.local_aabb) orelse continue;

            // 整个盒子都在射线起点背后：看不见，不能选。
            if (interval.exit < 0.0) continue;

            // 局部射线的方向做过同样的仿射变换但没有重新归一化，
            // 所以参数 t 与世界空间沿射线的距离完全一致。
            const distance = @max(interval.enter, 0.0);
            if (distance < camera.near_plane or distance > camera.far_plane) continue;

            if (closest) |current| {
                if (distance >= current.distance) continue;
            }

            closest = .{
                .object = object,
                .distance = distance,
                .point = ray.at(distance),
            };
        }

        return closest;
    }

    /// 屏幕坐标转世界空间射线。
    pub fn rayFromScreen(
        screen_x: f32,
        screen_y: f32,
        viewport: *const Viewport,
        camera: *const Camera,
    ) Ray {
        // 1. 屏幕坐标转 NDC
        const ndc = viewport.screenToNDC(screen_x, screen_y);

        // 2. 相机位置与朝向
        // 用 computePosition 而不是 transform.position：后者只在
        // update()/getViewMatrix() 里同步，拾取发生在它们之前会晚一帧。
        const origin = camera.computePosition();
        const forward = camera.transform.rotation.rotateVector(.{ 0.0, 0.0, -1.0 });
        const right = camera.transform.rotation.rotateVector(.{ 1.0, 0.0, 0.0 });
        const up = camera.transform.rotation.rotateVector(.{ 0.0, 1.0, 0.0 });

        // 3. NDC 在相机空间中的方向
        // 宽高比用视口的：camera.aspect_ratio 只在 resize 时更新，
        // 外部直接调用 resizeRenderer 时两者可能不一致。
        const tan_half_fov = @tan(camera.fov * std.math.pi / 360.0);
        const aspect = viewport.aspectRatio();
        const camera_x = ndc.x * tan_half_fov * aspect;
        const camera_y = ndc.y * tan_half_fov;

        const direction = [3]f32{
            forward[0] + camera_x * right[0] + camera_y * up[0],
            forward[1] + camera_x * right[1] + camera_y * up[1],
            forward[2] + camera_x * right[2] + camera_y * up[2],
        };

        // 4. 归一化，让 t 直接等于世界空间距离
        const length = vectorLength(direction);
        const normalized_direction = [3]f32{
            direction[0] / length,
            direction[1] / length,
            direction[2] / length,
        };

        return Ray.init(origin, normalized_direction);
    }

    fn vectorLength(v: [3]f32) f32 {
        return @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    }
};

// =============================================================================
// 测试
// =============================================================================

/// 单位立方体盒子，方便复用。
const unit_box = Aabb{
    .min = .{ -1.0, -1.0, -1.0 },
    .max = .{ 1.0, 1.0, 1.0 },
};

test "射线穿过盒子：区间是进入与离开的距离" {
    const ray = Ray.init(.{ 0.0, 0.0, -5.0 }, .{ 0.0, 0.0, 1.0 });
    const interval = ray.intersectsAabb(unit_box).?;

    try std.testing.expectApproxEqAbs(@as(f32, 4.0), interval.enter, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), interval.exit, 1e-5);
}

test "射线偏离盒子：不相交" {
    const ray = Ray.init(.{ 5.0, 0.0, -5.0 }, .{ 0.0, 0.0, 1.0 });
    try std.testing.expect(ray.intersectsAabb(unit_box) == null);
}

test "射线与盒子平行且在外面：不相交" {
    // y = 5 在盒子外面，而射线在 y 上没有分量
    const ray = Ray.init(.{ 0.0, 5.0, 0.0 }, .{ 1.0, 0.0, 0.0 });
    try std.testing.expect(ray.intersectsAabb(unit_box) == null);
}

test "射线与盒子平行但穿过：相交" {
    const ray = Ray.init(.{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.0, 0.0 });
    const interval = ray.intersectsAabb(unit_box).?;

    try std.testing.expectApproxEqAbs(@as(f32, -1.0), interval.enter, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), interval.exit, 1e-5);
}

test "空盒永远不相交" {
    const ray = Ray.init(.{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.0, 0.0 });
    try std.testing.expect(ray.intersectsAabb(Aabb.EMPTY) == null);
}

test "退化盒（某个轴零厚度）也能正常判定" {
    // Line / Rect 这类几何体在 z 上厚度为 0
    const flat = Aabb{ .min = .{ -1.0, -1.0, 0.0 }, .max = .{ 1.0, 1.0, 0.0 } };
    const ray = Ray.init(.{ 0.0, 0.0, -5.0 }, .{ 0.0, 0.0, 1.0 });
    const interval = ray.intersectsAabb(flat).?;

    try std.testing.expectApproxEqAbs(@as(f32, 5.0), interval.enter, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), interval.exit, 1e-5);
}

test "方向没归一化时，参数按方向长度缩放" {
    // 方向长度是 2：参数 2 才走到 z = -1，参数 3 走到 z = 1
    const ray = Ray.init(.{ 0.0, 0.0, -5.0 }, .{ 0.0, 0.0, 2.0 });
    const interval = ray.intersectsAabb(unit_box).?;

    try std.testing.expectApproxEqAbs(@as(f32, 2.0), interval.enter, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), interval.exit, 1e-5);
}

test "Ray.at 取射线上的点" {
    const ray = Ray.init(.{ 1.0, 2.0, 3.0 }, .{ 0.0, 0.0, 1.0 });
    const point = ray.at(4.0);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), point[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), point[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), point[2], 1e-5);
}

test "rayFromScreen：屏幕中心对应相机正前方，起点是相机位置" {
    var camera = Camera{};
    // 默认 distance = 3、单位旋转 → 相机在 (0, 0, 3)，朝 -Z
    const viewport = Viewport{ .x = 0.0, .y = 0.0, .width = 800.0, .height = 600.0 };

    const ray = Picker.rayFromScreen(400.0, 300.0, &viewport, &camera);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), ray.origin[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), ray.origin[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), ray.origin[2], 1e-4);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), ray.direction[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), ray.direction[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), ray.direction[2], 1e-4);
}

test "rayFromScreen：屏幕右上角对应相机右上方" {
    var camera = Camera{};
    const viewport = Viewport{ .x = 0.0, .y = 0.0, .width = 800.0, .height = 600.0 };

    // 屏幕右上：x 偏右、y 偏上
    const ray = Picker.rayFromScreen(800.0, 0.0, &viewport, &camera);

    try std.testing.expect(ray.direction[0] > 0.0);
    try std.testing.expect(ray.direction[1] > 0.0);
    try std.testing.expect(ray.direction[2] < 0.0);
}

test "Viewport.screenToNDC：左上角是 (-1, 1)" {
    const viewport = Viewport{ .x = 0.0, .y = 0.0, .width = 800.0, .height = 600.0 };

    const top_left = viewport.screenToNDC(0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), top_left.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), top_left.y, 1e-5);

    const bottom_right = viewport.screenToNDC(800.0, 600.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), bottom_right.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), bottom_right.y, 1e-5);
}
