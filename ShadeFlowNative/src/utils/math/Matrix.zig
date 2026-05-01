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

    // 创建平移矩阵
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
    
    // 4x4矩阵与3D向量乘法
    pub fn vectorMultiply4x4(matrix: [4][4]f32, vector: [3]f32) [3]f32 {
        const w = 1.0;
        const x = matrix[0][0] * vector[0] + matrix[0][1] * vector[1] + matrix[0][2] * vector[2] + matrix[0][3] * w;
        const y = matrix[1][0] * vector[0] + matrix[1][1] * vector[1] + matrix[1][2] * vector[2] + matrix[1][3] * w;
        const z = matrix[2][0] * vector[0] + matrix[2][1] * vector[1] + matrix[2][2] * vector[2] + matrix[2][3] * w;
        return [3]f32{ x, y, z };
    }
};
