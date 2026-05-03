const Quaternion = @import("../../utils/math/Quaternion.zig").Quaternion;
const Matrix = @import("../../utils/math/Matrix.zig").Matrix;
const std = @import("std");

// 变换结构体
pub const Transform = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: Quaternion = Quaternion{},
    scale: [3]f32 = .{ 1.0, 1.0, 1.0 },

    // 计算世界矩阵
    pub fn getWorldMatrix(self: *const Transform) [4][4]f32 {
        const translate_matrix = Matrix.createTranslationMatrix(self.position[0], self.position[1], self.position[2]);
        const rot_matrix = self.rotation.toMatrix();
        const scale_matrix = Matrix.createScaleMatrix(self.scale[0], self.scale[1], self.scale[2]);

        // 组合变换矩阵：缩放 -> 旋转 -> 平移
        var world_matrix = Matrix.matrixMultiply(scale_matrix, rot_matrix);
        world_matrix = Matrix.matrixMultiply(world_matrix, translate_matrix);
        return world_matrix;
    }

    // 更新（用于动画）
    pub fn update(self: *Transform, delta_time: f64) void {
        self.rotation = Quaternion.multiply(
            Quaternion.fromAxisAngle(.{ 0.0, 1.0, 0.0 }, @floatCast(0.5 * delta_time)),
            self.rotation,
        );
        // _ = delta_time;
        // _ = self.rotation;
    }
};
