const std = @import("std");

const Matrix = @import("../../utils/math/Matrix.zig").Matrix;
const Quaternion = @import("../../utils/math/Quaternion.zig").Quaternion;
const Transform = @import("../scene/Transform.zig").Transform;

pub const Camera = struct {
    transform: Transform = Transform{},

    target: [3]f32 = .{ 0.0, 0.0, 0.0 },

    fov: f32 = 45.0,
    aspect_ratio: f32 = 16.0 / 9.0,
    near_plane: f32 = 0.1,
    far_plane: f32 = 100.0,

    distance: f32 = 3.0,
    target_distance: f32 = 3.0,

    pub fn computePosition(self: *const Camera) [3]f32 {
        const offset = self.transform.rotation.rotateVector(.{ 0.0, 0.0, self.distance });
        return [3]f32{
            self.target[0] + offset[0],
            self.target[1] + offset[1],
            self.target[2] + offset[2],
        };
    }

    pub fn getViewMatrix(self: *Camera) [4][4]f32 {
        self.transform.position = self.computePosition();

        const cam_right = self.transform.rotation.rotateVector(.{ 1.0, 0.0, 0.0 });
        const cam_up = self.transform.rotation.rotateVector(.{ 0.0, 1.0, 0.0 });
        const cam_forward = self.transform.rotation.rotateVector(.{ 0.0, 0.0, -1.0 });

        return [4][4]f32{
            [4]f32{ cam_right[0], cam_up[0], -cam_forward[0], 0.0 },
            [4]f32{ cam_right[1], cam_up[1], -cam_forward[1], 0.0 },
            [4]f32{ cam_right[2], cam_up[2], -cam_forward[2], 0.0 },
            [4]f32{ -dotProduct(cam_right, self.transform.position), -dotProduct(cam_up, self.transform.position), dotProduct(cam_forward, self.transform.position), 1.0 },
        };
    }

    fn dotProduct(a: [3]f32, b: [3]f32) f32 {
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    }

    pub fn getProjectionMatrix(self: *const Camera) [4][4]f32 {
        const fov_rad = self.fov * std.math.pi / 180.0;
        const y_scale = 1.0 / @tan(fov_rad / 2.0);
        const x_scale = y_scale / self.aspect_ratio;
        const z_scale = -(self.far_plane + self.near_plane) / (self.far_plane - self.near_plane);
        const z_offset = (-2.0 * self.far_plane * self.near_plane) / (self.far_plane - self.near_plane);

        return [4][4]f32{
            [4]f32{ x_scale, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, y_scale, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, z_scale, -1.0 },
            [4]f32{ 0.0, 0.0, z_offset, 0.0 },
        };
    }

    pub fn update(self: *Camera) void {
        const smooth_factor = 0.1;
        self.distance += (self.target_distance - self.distance) * smooth_factor;
        self.transform.position = self.computePosition();
    }

    pub fn zoom(self: *Camera, delta: f32) void {
        self.target_distance -= delta * 0.01;
        if (self.target_distance < 0.1) self.target_distance = 0.1;
        if (self.target_distance > 10.0) self.target_distance = 10.0;
        self.distance = self.target_distance;
        self.transform.position = self.computePosition();
    }

    pub fn pan(self: *Camera, delta_x: f32, delta_y: f32) void {
        const pan_speed = 0.001 * self.distance;

        const cam_right = self.transform.rotation.rotateVector(.{ 1.0, 0.0, 0.0 });
        const cam_up = self.transform.rotation.rotateVector(.{ 0.0, 1.0, 0.0 });

        const move_x = -delta_x * pan_speed * cam_right[0] + delta_y * pan_speed * cam_up[0];
        const move_y = -delta_x * pan_speed * cam_right[1] + delta_y * pan_speed * cam_up[1];
        const move_z = -delta_x * pan_speed * cam_right[2] + delta_y * pan_speed * cam_up[2];

        self.transform.position[0] += move_x;
        self.transform.position[1] += move_y;
        self.transform.position[2] += move_z;

        self.target[0] += move_x;
        self.target[1] += move_y;
        self.target[2] += move_z;
    }

    // R' = dYaw_world * R * dPitch_local
    pub fn rotateAroundCenter(self: *Camera, delta_x: f32, delta_y: f32) void {
        const rotation_speed = 0.01;

        const dYaw = Quaternion.fromAxisAngle(.{ 0.0, 1.0, 0.0 }, delta_x * rotation_speed);
        const dPitch = Quaternion.fromAxisAngle(.{ 1.0, 0.0, 0.0 }, delta_y * rotation_speed);

        self.transform.rotation = Quaternion.multiply(dYaw, Quaternion.multiply(self.transform.rotation, dPitch));
        self.transform.position = self.computePosition();
    }

    pub fn rotateSelf(self: *Camera, delta_x: f32, delta_y: f32) void {
        const rotation_speed = 0.01;

        const dYaw = Quaternion.fromAxisAngle(.{ 0.0, 1.0, 0.0 }, delta_x * rotation_speed);
        const dPitch = Quaternion.fromAxisAngle(.{ 1.0, 0.0, 0.0 }, delta_y * rotation_speed);

        const combined = Quaternion.multiply(dYaw, dPitch);
        const cam_forward = self.transform.rotation.rotateVector(.{ 0.0, 0.0, -1.0 });
        const rotated_forward = combined.rotateVector(cam_forward);

        self.target[0] = self.transform.position[0] + rotated_forward[0] * self.distance;
        self.target[1] = self.transform.position[1] + rotated_forward[1] * self.distance;
        self.target[2] = self.transform.position[2] + rotated_forward[2] * self.distance;
    }

    pub fn setAspectRatio(self: *Camera, width: u32, height: u32) void {
        self.aspect_ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
    }
};
