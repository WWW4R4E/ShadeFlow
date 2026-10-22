const std = @import("std");

pub const Matrix = struct {

    // 矩阵乘法辅助函数
    pub fn matrixMultiply(a: [4][4]f32, b: [4][4]f32) [4][4]f32 {
        var result: [4][4]f32 = undefined;
        for (0..4) |i| {
            for (0..4) |j| {
                result[i][j] = 0.0;
                for (0..4) |k| {
                    result[i][j] += a[i][k] * b[k][j];
                }
            }
        }
        return result;
    }

    // 创建平移矩阵(DX默认是行主序vulkan默认列主序)
    pub fn createTranslationMatrix(x: f32, y: f32, z: f32) [4][4]f32 {
        return [4][4]f32{
            [4]f32{ 1.0, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, 1.0, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, 1.0, 0.0 },
            [4]f32{ x, y, z, 1.0 },
        };
    }

    // 创建X轴旋转矩阵
    pub fn createRotationXMatrix(angle: f32) [4][4]f32 {
        const c = @cos(angle);
        const s = @sin(angle);
        return [4][4]f32{
            [4]f32{ 1.0, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, c, -s, 0.0 },
            [4]f32{ 0.0, s, c, 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 1.0 },
        };
    }

    // 创建Y轴旋转矩阵
    pub fn createRotationYMatrix(angle: f32) [4][4]f32 {
        const c = @cos(angle);
        const s = @sin(angle);
        return [4][4]f32{
            [4]f32{ c, 0.0, s, 0.0 },
            [4]f32{ 0.0, 1.0, 0.0, 0.0 },
            [4]f32{ -s, 0.0, c, 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 1.0 },
        };
    }

    // 创建Z轴旋转矩阵
    pub fn createRotationZMatrix(angle: f32) [4][4]f32 {
        const c = @cos(angle);
        const s = @sin(angle);
        return [4][4]f32{
            [4]f32{ c, -s, 0.0, 0.0 },
            [4]f32{ s, c, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, 1.0, 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 1.0 },
        };
    }

    // 创建缩放矩阵
    pub fn createScaleMatrix(x: f32, y: f32, z: f32) [4][4]f32 {
        return [4][4]f32{
            [4]f32{ x, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, y, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, z, 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 1.0 },
        };
    }

    // 行向量约定：p * matrix。平移取 matrix[3][0..2]，与 createTranslationMatrix
    // 的布局一致。
    //
    // 注意：顶点着色器读同一块字节时按列主序解释（HLSL 默认 / GLSL std140），
    // 等价于计算 matrix^T * p，也就是这里这个 p * matrix，所以拾取、包围盒
    // 反算都能直接复用渲染的结果。
    pub fn transformPoint(matrix: [4][4]f32, point: [3]f32) [3]f32 {
        return .{
            point[0] * matrix[0][0] + point[1] * matrix[1][0] + point[2] * matrix[2][0] + matrix[3][0],
            point[0] * matrix[0][1] + point[1] * matrix[1][1] + point[2] * matrix[2][1] + matrix[3][1],
            point[0] * matrix[0][2] + point[1] * matrix[1][2] + point[2] * matrix[2][2] + matrix[3][2],
        };
    }

    // 行向量约定下的方向变换：与 transformPoint 相同，但不加平移。
    pub fn transformDirection(matrix: [4][4]f32, direction: [3]f32) [3]f32 {
        return .{
            direction[0] * matrix[0][0] + direction[1] * matrix[1][0] + direction[2] * matrix[2][0],
            direction[0] * matrix[0][1] + direction[1] * matrix[1][1] + direction[2] * matrix[2][1],
            direction[0] * matrix[0][2] + direction[1] * matrix[1][2] + direction[2] * matrix[2][2],
        };
    }

    // 求行向量约定下的仿射矩阵的逆矩阵。
    //
    // 要求矩阵形如 [[L, 0], [t, 1]]（末列 0,0,0,1、末行为平移），
    // `Transform.getWorldMatrix` 产出的 T*R*S 满足这个形式。
    // 3x3 部分不可逆（例如某个轴缩放为 0）时返回 null。
    pub fn invertAffine(matrix: [4][4]f32) ?[4][4]f32 {
        const a = matrix[0][0];
        const b = matrix[0][1];
        const c = matrix[0][2];
        const d = matrix[1][0];
        const e = matrix[1][1];
        const f = matrix[1][2];
        const g = matrix[2][0];
        const h = matrix[2][1];
        const i = matrix[2][2];

        // 3x3 行列式与伴随矩阵；余子式按行主序写开。
        const cofactor_a = e * i - f * h;
        const cofactor_b = f * g - d * i;
        const cofactor_c = d * h - e * g;
        const determinant = a * cofactor_a + b * cofactor_b + c * cofactor_c;
        if (@abs(determinant) < 1e-12) return null;
        const inverse_determinant = 1.0 / determinant;

        const inverse_00 = cofactor_a * inverse_determinant;
        const inverse_01 = (c * h - b * i) * inverse_determinant;
        const inverse_02 = (b * f - c * e) * inverse_determinant;
        const inverse_10 = cofactor_b * inverse_determinant;
        const inverse_11 = (a * i - c * g) * inverse_determinant;
        const inverse_12 = (c * d - a * f) * inverse_determinant;
        const inverse_20 = cofactor_c * inverse_determinant;
        const inverse_21 = (b * g - a * h) * inverse_determinant;
        const inverse_22 = (a * e - b * d) * inverse_determinant;

        // 逆矩阵的平移 = -(t * L^-1)。
        const tx = matrix[3][0];
        const ty = matrix[3][1];
        const tz = matrix[3][2];

        return [4][4]f32{
            .{ inverse_00, inverse_01, inverse_02, 0.0 },
            .{ inverse_10, inverse_11, inverse_12, 0.0 },
            .{ inverse_20, inverse_21, inverse_22, 0.0 },
            .{
                -(tx * inverse_00 + ty * inverse_10 + tz * inverse_20),
                -(tx * inverse_01 + ty * inverse_11 + tz * inverse_21),
                -(tx * inverse_02 + ty * inverse_12 + tz * inverse_22),
                1.0,
            },
        };
    }

    // 4x4矩阵与3D向量乘法
    pub fn vectorMultiply4x4(matrix: [4][4]f32, vector: [3]f32) [3]f32 {
        const w = 1.0;
        const x = matrix[0][0] * vector[0] + matrix[0][1] * vector[1] + matrix[0][2] * vector[2] + matrix[0][3] * w;
        const y = matrix[1][0] * vector[0] + matrix[1][1] * vector[1] + matrix[1][2] * vector[2] + matrix[1][3] * w;
        const z = matrix[2][0] * vector[0] + matrix[2][1] * vector[1] + matrix[2][2] * vector[2] + matrix[2][3] * w;
        return [3]f32{ x, y, z };
    }
};

// =============================================================================
// 测试
// =============================================================================

test "transformPoint 走行向量约定 p * matrix：平移生效" {
    const translation = Matrix.createTranslationMatrix(1.0, 2.0, 3.0);
    const moved = Matrix.transformPoint(translation, .{ 0.5, 0.5, 0.5 });

    try std.testing.expectApproxEqAbs(@as(f32, 1.5), moved[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), moved[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3.5), moved[2], 1e-5);
}

test "transformPoint 走行向量约定 p * matrix：缩放生效" {
    const scale = Matrix.createScaleMatrix(2.0, 3.0, 4.0);
    const scaled = Matrix.transformPoint(scale, .{ 1.0, 1.0, 1.0 });

    try std.testing.expectApproxEqAbs(@as(f32, 2.0), scaled[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), scaled[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), scaled[2], 1e-5);
}

test "transformDirection 不含平移" {
    const translation = Matrix.createTranslationMatrix(10.0, 20.0, 30.0);
    const direction = Matrix.transformDirection(translation, .{ 1.0, 0.0, 0.0 });

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), direction[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), direction[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), direction[2], 1e-5);
}

test "invertAffine 与 transformPoint 互为逆运算" {
    // 世界矩阵的形状：T * R * S（行向量约定下先缩放、再旋转、最后平移）
    const matrix = Matrix.matrixMultiply(
        Matrix.createTranslationMatrix(3.0, -1.0, 2.0),
        Matrix.matrixMultiply(
            Matrix.createRotationYMatrix(0.7),
            Matrix.createScaleMatrix(2.0, 2.0, 2.0),
        ),
    );

    const inverse = Matrix.invertAffine(matrix).?;
    const point = [3]f32{ 1.0, 2.0, 3.0 };
    const round_trip = Matrix.transformPoint(inverse, Matrix.transformPoint(matrix, point));

    for (0..3) |axis| {
        try std.testing.expectApproxEqAbs(point[axis], round_trip[axis], 1e-4);
    }
}

test "invertAffine 还原平移" {
    const matrix = Matrix.createTranslationMatrix(1.0, -2.0, 3.0);
    const inverse = Matrix.invertAffine(matrix).?;
    const moved = Matrix.transformPoint(inverse, .{ 1.0, -2.0, 3.0 });

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), moved[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), moved[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), moved[2], 1e-5);
}

test "invertAffine 在 3x3 不可逆时返回 null" {
    // 某个轴缩放为 0：行列式为 0，没有逆
    try std.testing.expect(Matrix.invertAffine(Matrix.createScaleMatrix(1.0, 0.0, 1.0)) == null);
}
