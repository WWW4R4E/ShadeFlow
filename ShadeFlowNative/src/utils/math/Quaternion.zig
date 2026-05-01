const std = @import("std");

pub const Quaternion = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 1.0,

    pub const identity = Quaternion{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };

    pub fn fromAxisAngle(axis: [3]f32, angle: f32) Quaternion {
        const length = std.math.sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
        if (length <= 0.0) return identity;

        const normalized_axis = [3]f32{ axis[0] / length, axis[1] / length, axis[2] / length };
        const half_angle = angle * 0.5;
        const sin_half = @sin(half_angle);
        return .{
            .x = normalized_axis[0] * sin_half,
            .y = normalized_axis[1] * sin_half,
            .z = normalized_axis[2] * sin_half,
            .w = @cos(half_angle),
        };
    }

    pub fn multiply(a: Quaternion, b: Quaternion) Quaternion {
        return .{
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        };
    }

    pub fn rotateVector(self: Quaternion, v: [3]f32) [3]f32 {
        const qv = Quaternion{ .x = v[0], .y = v[1], .z = v[2], .w = 0.0 };
        const q_conj = Quaternion{ .x = -self.x, .y = -self.y, .z = -self.z, .w = self.w };
        const result = Quaternion.multiply(Quaternion.multiply(self, qv), q_conj);
        return [3]f32{ result.x, result.y, result.z };
    }

    pub fn normalize(self: Quaternion) Quaternion {
        const length = std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        if (length <= 0.0) return identity;
        return .{
            .x = self.x / length,
            .y = self.y / length,
            .z = self.z / length,
            .w = self.w / length,
        };
    }

    pub fn toMatrix(self: Quaternion) [4][4]f32 {
        const q = self.normalize();
        const x2 = q.x * q.x;
        const y2 = q.y * q.y;
        const z2 = q.z * q.z;
        const xy = q.x * q.y;
        const xz = q.x * q.z;
        const yz = q.y * q.z;
        const wx = q.w * q.x;
        const wy = q.w * q.y;
        const wz = q.w * q.z;

        return [4][4]f32{
            [4]f32{ 1.0 - 2.0 * (y2 + z2), 2.0 * (xy + wz), 2.0 * (xz - wy), 0.0 },
            [4]f32{ 2.0 * (xy - wz), 1.0 - 2.0 * (x2 + z2), 2.0 * (yz + wx), 0.0 },
            [4]f32{ 2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (x2 + y2), 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 1.0 },
        };
    }
};
