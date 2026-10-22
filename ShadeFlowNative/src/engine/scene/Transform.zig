const Quaternion = @import("../math/Quaternion.zig").Quaternion;
const Matrix = @import("../math/Matrix.zig").Matrix;
const std = @import("std");

// 变换结构体
pub const Transform = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: Quaternion = Quaternion{},
    scale: [3]f32 = .{ 1.0, 1.0, 1.0 },

    // 计算世界矩阵。
    //
    // 行向量约定（`p * M`，与顶点着色器 / `Matrix.transformPoint` 一致），
    // 组合顺序必须是 缩放 -> 旋转 -> 平移，即 S*R*T：
    //     world = R(S * local) + position
    //
    // 写成 T*R*S 会让平移也参与旋转和缩放，物体表面看是"绕原点公转"，
    // 而不是停在 position 上自转。
    pub fn getWorldMatrix(self: *const Transform) [4][4]f32 {
        const translate_matrix = Matrix.createTranslationMatrix(self.position[0], self.position[1], self.position[2]);
        const rot_matrix = self.rotation.toMatrix();
        const scale_matrix = Matrix.createScaleMatrix(self.scale[0], self.scale[1], self.scale[2]);

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
