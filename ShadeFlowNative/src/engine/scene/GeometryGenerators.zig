const std = @import("std");

// `Vertex` 定义在渲染层中立的 `render/Types.zig`。但那个文件是独立模块
// `render_types` 的根——Zig 规定一个文件只能属于一个模块，所以不能用相对
// 路径 import 它；要走门面 `render/Renderer.zig` 转出的 `Types`（命名模块）。
// 也因此本文件不再反向 import `../Engine.zig`（文件级循环随之断掉）。
const Types = @import("../render/Renderer.zig").Types;
const Vertex = Types.Vertex;
const VertexTex = Types.VertexTex;

/// 带纹理几何：`generateCubeUV` 的返回类型。
pub const TexGeometry = struct {
    vertices: []VertexTex,
    indices: []u32,
};

// 几何形状参数结构
pub const GeometryGenerators = struct {
    /// 生成结果。用具名类型而不是每处 `struct { ... }`，调用方才能把
    /// `switch` 各分支统一到同一个类型。
    pub const Geometry = struct {
        vertices: []Vertex,
        indices: []u32,
    };

    // 立方体参数
    pub const CubeParams = struct {
        size: f32 = 1.0, // 立方体大小
    };

    // 球体参数
    pub const SphereParams = struct {
        radius: f32 = 0.5, // 球体半径
        segments: u32 = 32, // 分段数
    };

    // 圆柱体参数
    pub const CylinderParams = struct {
        radius: f32 = 0.5, // 半径
        height: f32 = 1.0, // 高度
        segments: u32 = 32, // 分段数
    };

    // 圆锥体参数
    pub const ConeParams = struct {
        radius: f32 = 0.5, // 底面半径
        height: f32 = 1.0, // 高度
        segments: u32 = 32, // 分段数
    };

    // 线段参数
    pub const LineParams = struct {
        x1: f32 = 0.0, // 起点x
        y1: f32 = 0.0, // 起点y
        x2: f32 = 1.0, // 终点x
        y2: f32 = 1.0, // 终点y
        z: f32 = 0.0, // z坐标
    };

    // 矩形参数
    pub const RectParams = struct {
        x: f32 = 0.0, // 左上角x
        y: f32 = 0.0, // 左上角y
        width: f32 = 1.0, // 宽度
        height: f32 = 1.0, // 高度
        z: f32 = 0.0, // z坐标
    };

    // 几何形状参数联合体
    pub const GeometryParams = union(enum) {
        Cube: CubeParams,
        Sphere: SphereParams,
        Cylinder: CylinderParams,
        Cone: ConeParams,
        Line: LineParams,
        Rect: RectParams,
        FilledRect: RectParams,
    };

    // 几何形状类型
    pub const GeometryType = enum(c_int) {
        Triangle = 0,
        Quad = 1,
        Cube = 2,
        Sphere = 3,
        Cylinder = 4,
        Cone = 5,
        Line = 6,
        Rect = 7,
        FilledRect = 8,
    };

    // 动态几何生成函数

    // 生成立方体
    /// 带纹理 UV 的立方体：6 个面各自独立 4 顶点（UV 需要每面独立映射，
    /// 共享顶点的写法没法给每个面完整的 0..1 UV），每面 UV 0..1。
    pub fn generateCubeUV(allocator: std.mem.Allocator, params: CubeParams) !TexGeometry {
        const half = params.size / 2.0;

        // 每面：4 顶点 + 2 三角形。面按 (origin, u 轴, v 轴) 生成。
        const faces = [_]struct {
            origin: [3]f32,
            u: [3]f32,
            v: [3]f32,
        }{
            // 前面 z+（从外看逆时针排 u/v）
            .{ .origin = .{ -half, -half, half }, .u = .{ 2 * half, 0, 0 }, .v = .{ 0, 2 * half, 0 } },
            // 后面 z-
            .{ .origin = .{ half, -half, -half }, .u = .{ -2 * half, 0, 0 }, .v = .{ 0, 2 * half, 0 } },
            // 右面 x+
            .{ .origin = .{ half, -half, half }, .u = .{ 0, 0, -2 * half }, .v = .{ 0, 2 * half, 0 } },
            // 左面 x-
            .{ .origin = .{ -half, -half, -half }, .u = .{ 0, 0, 2 * half }, .v = .{ 0, 2 * half, 0 } },
            // 顶面 y+
            .{ .origin = .{ -half, half, half }, .u = .{ 2 * half, 0, 0 }, .v = .{ 0, 0, -2 * half } },
            // 底面 y-
            .{ .origin = .{ -half, -half, -half }, .u = .{ 2 * half, 0, 0 }, .v = .{ 0, 0, 2 * half } },
        };

        var vertices = try allocator.alloc(VertexTex, 24);
        errdefer allocator.free(vertices);
        var indices = try allocator.alloc(u32, 36);
        errdefer allocator.free(indices);

        for (faces, 0..) |face, fi| {
            const base: u32 = @intCast(fi * 4);
            const corners = [4][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 } };
            // 面的法线 = normalize(u × v)——面的 (origin,u,v) 张成外向平面。
            const u = face.u;
            const v = face.v;
            var normal = [3]f32{
                u[1] * v[2] - u[2] * v[1],
                u[2] * v[0] - u[0] * v[2],
                u[0] * v[1] - u[1] * v[0],
            };
            const len = std.math.sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]);
            normal[0] /= len;
            normal[1] /= len;
            normal[2] /= len;

            for (corners, 0..) |c, ci| {
                vertices[base + ci] = .{
                    .position = .{
                        face.origin[0] + face.u[0] * c[0] + face.v[0] * c[1],
                        face.origin[1] + face.u[1] * c[0] + face.v[1] * c[1],
                        face.origin[2] + face.u[2] * c[0] + face.v[2] * c[1],
                    },
                    .normal = normal,
                    .uv = c,
                };
            }
            const ii: u32 = @intCast(fi * 6);
            indices[ii] = base;
            indices[ii + 1] = base + 1;
            indices[ii + 2] = base + 2;
            indices[ii + 3] = base;
            indices[ii + 4] = base + 2;
            indices[ii + 5] = base + 3;
        }

        return .{ .vertices = vertices, .indices = indices };
    }

    /// 立方体（顶点色路径）：与 generateCubeUV 同款逐面 24 顶点写法——
    /// 8 顶点共享的版本没法给每个面正确的法线，光照会糊。
    pub fn generateCube(allocator: std.mem.Allocator, params: CubeParams) !Geometry {
        const uv_cube = try generateCubeUV(allocator, params);
        defer {
            allocator.free(uv_cube.vertices);
            allocator.free(uv_cube.indices);
        }

        var vertices = try allocator.alloc(Vertex, uv_cube.vertices.len);
        errdefer allocator.free(vertices);
        for (uv_cube.vertices, 0..) |v, i| {
            vertices[i] = .{ .position = v.position, .normal = v.normal };
        }
        const indices = try allocator.dupe(u32, uv_cube.indices);
        errdefer allocator.free(indices);

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成球体
    pub fn generateSphere(allocator: std.mem.Allocator, params: SphereParams) !Geometry {
        const radius = params.radius;
        const segments = params.segments;

        // 计算顶点数和索引数
        const vertex_count = (segments + 1) * (segments + 1);
        const index_count = segments * segments * 6;

        var vertices = try allocator.alloc(Vertex, vertex_count);
        var indices = try allocator.alloc(u32, index_count);

        // 生成顶点
        var i: u32 = 0;
        for (0..segments + 1) |lat| {
            const theta = @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(segments)) * std.math.pi;
            const sin_theta = std.math.sin(theta);
            const cos_theta = std.math.cos(theta);

            for (0..segments + 1) |lon| {
                const phi = @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(segments)) * 2.0 * std.math.pi;
                const sin_phi = std.math.sin(phi);
                const cos_phi = std.math.cos(phi);

                const px = radius * sin_theta * cos_phi;
                const py = radius * cos_theta;
                const pz = radius * sin_theta * sin_phi;
                vertices[i] = Vertex{
                    .position = .{ px, py, pz },
                    // 球面法线 = 单位化后的位置向量（原点在球心）。
                    .normal = .{ sin_theta * cos_phi, cos_theta, sin_theta * sin_phi },
                };
                i += 1;
            }
        }

        // 生成索引
        i = 0;
        for (0..segments) |lat| {
            for (0..segments) |lon| {
                const first = @as(u32, @intCast(lat * (segments + 1) + lon));
                const second = @as(u32, @intCast(first + segments + 1));

                indices[i] = first;
                indices[i + 1] = second;
                indices[i + 2] = first + 1;

                indices[i + 3] = second;
                indices[i + 4] = second + 1;
                indices[i + 5] = first + 1;

                i += 6;
            }
        }

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成圆柱体
    pub fn generateCylinder(allocator: std.mem.Allocator, params: CylinderParams) !Geometry {
        const radius = params.radius;
        const height = params.height;
        const segments = params.segments;

        const half_height = height / 2.0;

        // 计算顶点数和索引数
        const vertex_count = segments * 2 + 2; // 侧面+顶面+底面
        const index_count = segments * 6 + segments * 6; // 侧面三角形+顶面三角形+底面三角形

        var vertices = try allocator.alloc(Vertex, vertex_count);
        var indices = try allocator.alloc(u32, index_count);

        // 生成顶点
        var i: u32 = 0;

        // 顶面中心
        vertices[i] = Vertex{ .position = .{ 0.0, half_height, 0.0 }, .normal = .{ 0, 1, 0 } };
        i += 1;

        // 底面中心
        vertices[i] = Vertex{ .position = .{ 0.0, -half_height, 0.0 }, .normal = .{ 0, -1, 0 } };
        i += 1;

        // 侧面顶点（顶/底环共用水平径向法线）
        for (0..segments) |seg| {
            const angle = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments)) * 2.0 * std.math.pi;
            const x = radius * std.math.cos(angle);
            const z = radius * std.math.sin(angle);

            vertices[i] = Vertex{ .position = .{ x, half_height, z }, .normal = .{ std.math.cos(angle), 0, std.math.sin(angle) } };
            i += 1;

            vertices[i] = Vertex{ .position = .{ x, -half_height, z }, .normal = .{ std.math.cos(angle), 0, std.math.sin(angle) } };
            i += 1;
        }

        // 生成索引
        i = 0;

        // 顶面三角形
        for (0..segments) |seg| {
            indices[i] = 0;
            indices[i + 1] = @as(u32, @intCast(2 + seg * 2));
            indices[i + 2] = @as(u32, @intCast(2 + ((seg + 1) % segments) * 2));
            i += 3;
        }

        // 底面三角形（逆时针顺序）
        for (0..segments) |seg| {
            indices[i] = 1;
            indices[i + 1] = @as(u32, @intCast(3 + ((seg + 1) % segments) * 2));
            indices[i + 2] = @as(u32, @intCast(3 + seg * 2));
            i += 3;
        }

        // 侧面四边形（分解为两个三角形）
        for (0..segments) |seg| {
            const next_seg = (seg + 1) % segments;

            indices[i] = @as(u32, @intCast(2 + seg * 2));
            indices[i + 1] = @as(u32, @intCast(3 + seg * 2));
            indices[i + 2] = @as(u32, @intCast(2 + next_seg * 2));

            indices[i + 3] = @as(u32, @intCast(3 + seg * 2));
            indices[i + 4] = @as(u32, @intCast(3 + next_seg * 2));
            indices[i + 5] = @as(u32, @intCast(2 + next_seg * 2));

            i += 6;
        }

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成圆锥体
    pub fn generateCone(allocator: std.mem.Allocator, params: ConeParams) !Geometry {
        const radius = params.radius;
        const height = params.height;
        const segments = params.segments;

        const half_height = height / 2.0;

        // 计算顶点数和索引数
        const vertex_count = segments + 2; // 顶点+底面中心+底面边缘
        const index_count = segments * 3 + segments * 3; // 侧面三角形+底面三角形

        var vertices = try allocator.alloc(Vertex, vertex_count);
        var indices = try allocator.alloc(u32, index_count);

        // 生成顶点
        var i: u32 = 0;

        // 顶点（锥面法线在顶点处取底缘斜率的近似，视觉上够用）
        vertices[i] = Vertex{ .position = .{ 0.0, half_height, 0.0 }, .normal = .{ 0, 1, 0 } };
        i += 1;

        // 底面中心
        vertices[i] = Vertex{ .position = .{ 0.0, -half_height, 0.0 }, .normal = .{ 0, -1, 0 } };
        i += 1;

        // 底面边缘顶点
        const slope = radius / height; // 锥面斜率 → 法线的 y 分量
        for (0..segments) |seg| {
            const angle = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments)) * 2.0 * std.math.pi;
            const x = radius * std.math.cos(angle);
            const z = radius * std.math.sin(angle);

            vertices[i] = Vertex{ .position = .{ x, -half_height, z }, .normal = .{ std.math.cos(angle), slope, std.math.sin(angle) } };
            i += 1;
        }

        // 生成索引
        i = 0;

        // 侧面三角形
        for (0..segments) |seg| {
            indices[i] = 0;
            indices[i + 1] = @as(u32, @intCast(2 + seg));
            indices[i + 2] = @as(u32, @intCast(2 + ((seg + 1) % segments)));
            i += 3;
        }

        // 底面三角形（逆时针顺序）
        for (0..segments) |seg| {
            indices[i] = 1;
            indices[i + 1] = @as(u32, @intCast(2 + ((seg + 1) % segments)));
            indices[i + 2] = @as(u32, @intCast(2 + seg));
            i += 3;
        }

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成线段
    pub fn generateLine(allocator: std.mem.Allocator, params: LineParams) !Geometry {
        var vertices = try allocator.alloc(Vertex, 2);
        vertices[0] = Vertex{ .position = [3]f32{ params.x1, params.y1, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };
        vertices[1] = Vertex{ .position = [3]f32{ params.x2, params.y2, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };

        var indices = try allocator.alloc(u32, 2);
        indices[0] = 0;
        indices[1] = 1;

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成矩形边框
    pub fn generateRect(allocator: std.mem.Allocator, params: RectParams) !Geometry {
        var vertices = try allocator.alloc(Vertex, 4);
        vertices[0] = Vertex{ .position = [3]f32{ params.x, params.y, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };
        vertices[1] = Vertex{ .position = [3]f32{ params.x + params.width, params.y, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };
        vertices[2] = Vertex{ .position = [3]f32{ params.x + params.width, params.y + params.height, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };
        vertices[3] = Vertex{ .position = [3]f32{ params.x, params.y + params.height, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };

        // 使用LINESTRIP需要4个顶点，索引为0,1,2,3,0
        var indices = try allocator.alloc(u32, 5);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        indices[3] = 3;
        indices[4] = 0;

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成填充矩形
    pub fn generateFilledRect(allocator: std.mem.Allocator, params: RectParams) !Geometry {
        var vertices = try allocator.alloc(Vertex, 4);
        vertices[0] = Vertex{ .position = [3]f32{ params.x, params.y, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };
        vertices[1] = Vertex{ .position = [3]f32{ params.x + params.width, params.y, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };
        vertices[2] = Vertex{ .position = [3]f32{ params.x + params.width, params.y + params.height, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };
        vertices[3] = Vertex{ .position = [3]f32{ params.x, params.y + params.height, params.z }, .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 } };

        // 两个三角形: 0,1,2 和 0,2,3
        var indices = try allocator.alloc(u32, 6);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        indices[3] = 0;
        indices[4] = 2;
        indices[5] = 3;

        return .{ .vertices = vertices, .indices = indices };
    }
};
