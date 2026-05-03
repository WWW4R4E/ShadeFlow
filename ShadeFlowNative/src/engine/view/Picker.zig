const std = @import("std");
const Camera = @import("Camera.zig").Camera;
const Object = @import("../scene/Object.zig").Object;
const Matrix = @import("../../utils/math/Matrix.zig").Matrix;

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

pub const Ray = struct {
    origin: [3]f32,
    direction: [3]f32,

    pub fn init(origin: [3]f32, direction: [3]f32) Ray {
        return Ray{
            .origin = origin,
            .direction = direction,
        };
    }

    // 检测射线是否与包围球相交
    pub fn intersectsSphere(self: Ray, center: [3]f32, radius: f32) bool {
        const oc = [3]f32{
            self.origin[0] - center[0],
            self.origin[1] - center[1],
            self.origin[2] - center[2],
        };

        const a = self.direction[0] * self.direction[0] +
            self.direction[1] * self.direction[1] +
            self.direction[2] * self.direction[2];

        const b = 2.0 * (oc[0] * self.direction[0] +
            oc[1] * self.direction[1] +
            oc[2] * self.direction[2]);

        const c = oc[0] * oc[0] + oc[1] * oc[1] + oc[2] * oc[2] - radius * radius;

        const discriminant = b * b - 4.0 * a * c;
        return discriminant >= 0.0;
    }
};

pub const Picker = struct {
    pub fn pick(
        screen_x: f32,
        screen_y: f32,
        viewport: *const Viewport,
        camera: *const Camera,
        objects: []*Object,
    ) ?*Object {
        // 1. 屏幕坐标转NDC
        const ndc = viewport.screenToNDC(screen_x, screen_y);

        // 2. NDC转世界空间射线
        const ray = screenPointToRay(ndc.x, ndc.y, camera);

        // 3. 遍历物体进行射线检测
        var closest_object: ?*Object = null;
        var closest_distance: f32 = std.math.inf(f32);

        for (objects) |object| {
            // 获取物体位置（中心点）
            const center = object.transform.position;

            // 使用固定半径（可以根据需要调整，或者从物体的顶点数据计算）
            const radius = 0.5;

            // 检测射线是否与包围球相交
            if (ray.intersectsSphere(center, radius)) {
                // 计算射线到物体的距离（简化计算）
                const distance = vectorLength([3]f32{
                    center[0] - ray.origin[0],
                    center[1] - ray.origin[1],
                    center[2] - ray.origin[2],
                });

                // 选择最近的物体
                if (distance < closest_distance) {
                    closest_distance = distance;
                    closest_object = object;
                }
            }
        }

        return closest_object;
    }

    fn screenPointToRay(ndc_x: f32, ndc_y: f32, camera: *const Camera) Ray {
        // 获取相机位置作为射线起点
        const origin = camera.transform.position;

        // 获取相机方向向量
        const forward = camera.transform.rotation.rotateVector(.{ 0.0, 0.0, -1.0 });
        const right = camera.transform.rotation.rotateVector(.{ 1.0, 0.0, 0.0 });
        const up = camera.transform.rotation.rotateVector(.{ 0.0, 1.0, 0.0 });

        // 计算NDC在相机空间中的方向
        const tan_half_fov = @tan(camera.fov * std.math.pi / 360.0);
        const aspect = camera.aspect_ratio;

        // NDC到相机空间
        const camera_x = ndc_x * tan_half_fov * aspect;
        const camera_y = ndc_y * tan_half_fov;

        // 组合方向向量
        const direction = [3]f32{
            forward[0] + camera_x * right[0] + camera_y * up[0],
            forward[1] + camera_x * right[1] + camera_y * up[1],
            forward[2] + camera_x * right[2] + camera_y * up[2],
        };

        // 归一化方向向量
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
