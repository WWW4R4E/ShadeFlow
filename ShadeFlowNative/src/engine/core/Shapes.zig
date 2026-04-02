const std = @import("std");

const Engine = @import("Engine.zig").Engine;
const Vertex = @import("Engine.zig").Vertex;

pub const Shapes = struct {

    // 几何形状参数结构

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

    // 几何形状参数联合体
    pub const GeometryParams = union(enum) {
        Cube: CubeParams,
        Sphere: SphereParams,
        Cylinder: CylinderParams,
        Cone: ConeParams,
    };

    // 几何形状类型
    pub const GeometryType = enum(c_int) {
        Triangle = 0,
        Quad = 1,
        Cube = 2,
        Sphere = 3,
        Cylinder = 4,
        Cone = 5,
    };
    // 动态几何生成函数

    // 生成立方体
    fn generateCube(allocator: std.mem.Allocator, params: CubeParams) !struct { vertices: []Vertex, indices: []u16 } {
        const half_size = params.size / 2.0;

        // 立方体有8个顶点
        var vertices = try allocator.alloc(Vertex, 8);
        vertices[0] = Vertex{ .position = [3]f32{ -half_size, -half_size, half_size } }; // 左下前
        vertices[1] = Vertex{ .position = [3]f32{ half_size, -half_size, half_size } }; // 右下前
        vertices[2] = Vertex{ .position = [3]f32{ half_size, half_size, half_size } }; // 右上前
        vertices[3] = Vertex{ .position = [3]f32{ -half_size, half_size, half_size } }; // 左上前
        vertices[4] = Vertex{ .position = [3]f32{ -half_size, -half_size, -half_size } }; // 左下后
        vertices[5] = Vertex{ .position = [3]f32{ half_size, -half_size, -half_size } }; // 右下后
        vertices[6] = Vertex{ .position = [3]f32{ half_size, half_size, -half_size } }; // 右上后
        vertices[7] = Vertex{ .position = [3]f32{ -half_size, half_size, -half_size } }; // 左上后

        var indices = try allocator.alloc(u16, 36);
        // 前面
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        indices[3] = 0;
        indices[4] = 2;
        indices[5] = 3;
        // 顶面
        indices[6] = 3;
        indices[7] = 2;
        indices[8] = 6;
        indices[9] = 3;
        indices[10] = 6;
        indices[11] = 7;
        // 右面
        indices[12] = 2;
        indices[13] = 1;
        indices[14] = 5;
        indices[15] = 2;
        indices[16] = 5;
        indices[17] = 6;
        // 底面
        indices[18] = 0;
        indices[19] = 4;
        indices[20] = 5;
        indices[21] = 0;
        indices[22] = 5;
        indices[23] = 1;
        // 左面
        indices[24] = 0;
        indices[25] = 3;
        indices[26] = 7;
        indices[27] = 0;
        indices[28] = 7;
        indices[29] = 4;
        // 后面
        indices[30] = 4;
        indices[31] = 7;
        indices[32] = 6;
        indices[33] = 4;
        indices[34] = 6;
        indices[35] = 5;

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成球体
    fn generateSphere(allocator: std.mem.Allocator, params: SphereParams) !struct { vertices: []Vertex, indices: []u16 } {
        const radius = params.radius;
        const segments = params.segments;

        // 计算顶点数和索引数
        const vertex_count = (segments + 1) * (segments + 1);
        const index_count = segments * segments * 6;

        var vertices = try allocator.alloc(Vertex, vertex_count);
        var indices = try allocator.alloc(u16, index_count);

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

                vertices[i] = Vertex{ .position = [3]f32{
                    radius * sin_theta * cos_phi,
                    radius * cos_theta,
                    radius * sin_theta * sin_phi,
                } };
                i += 1;
            }
        }

        // 生成索引
        i = 0;
        for (0..segments) |lat| {
            for (0..segments) |lon| {
                const first = @as(u16, @intCast(lat * (segments + 1) + lon));
                const second = @as(u16, @intCast(first + segments + 1));

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
    fn generateCylinder(allocator: std.mem.Allocator, params: CylinderParams) !struct { vertices: []Vertex, indices: []u16 } {
        const radius = params.radius;
        const height = params.height;
        const segments = params.segments;

        const half_height = height / 2.0;

        // 计算顶点数和索引数
        const vertex_count = segments * 2 + 2; // 侧面+顶面+底面
        const index_count = segments * 6 + segments * 6; // 侧面三角形+顶面三角形+底面三角形

        var vertices = try allocator.alloc(Vertex, vertex_count);
        var indices = try allocator.alloc(u16, index_count);

        // 生成顶点
        var i: u32 = 0;

        // 顶面中心
        vertices[i] = Vertex{ .position = [3]f32{ 0.0, half_height, 0.0 } };
        i += 1;

        // 底面中心
        vertices[i] = Vertex{ .position = [3]f32{ 0.0, -half_height, 0.0 } };
        i += 1;

        // 侧面顶点
        for (0..segments) |seg| {
            const angle = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments)) * 2.0 * std.math.pi;
            const x = radius * std.math.cos(angle);
            const z = radius * std.math.sin(angle);

            // 顶面顶点
            vertices[i] = Vertex{ .position = [3]f32{ x, half_height, z } };
            i += 1;

            // 底面顶点
            vertices[i] = Vertex{ .position = [3]f32{ x, -half_height, z } };
            i += 1;
        }

        // 生成索引
        i = 0;

        // 顶面三角形
        for (0..segments) |seg| {
            indices[i] = 0;
            indices[i + 1] = @as(u16, @intCast(2 + seg * 2));
            indices[i + 2] = @as(u16, @intCast(2 + ((seg + 1) % segments) * 2));
            i += 3;
        }

        // 底面三角形
        for (0..segments) |seg| {
            indices[i] = 1;
            indices[i + 1] = @as(u16, @intCast(3 + seg * 2));
            indices[i + 2] = @as(u16, @intCast(3 + ((seg + 1) % segments) * 2));
            i += 3;
        }

        // 侧面四边形（分解为两个三角形）
        for (0..segments) |seg| {
            const next_seg = (seg + 1) % segments;

            indices[i] = @as(u16, @intCast(2 + seg * 2));
            indices[i + 1] = @as(u16, @intCast(3 + seg * 2));
            indices[i + 2] = @as(u16, @intCast(2 + next_seg * 2));

            indices[i + 3] = @as(u16, @intCast(3 + seg * 2));
            indices[i + 4] = @as(u16, @intCast(3 + next_seg * 2));
            indices[i + 5] = @as(u16, @intCast(2 + next_seg * 2));

            i += 6;
        }

        return .{ .vertices = vertices, .indices = indices };
    }

    // 生成圆锥体
    fn generateCone(allocator: std.mem.Allocator, params: ConeParams) !struct { vertices: []Vertex, indices: []u16 } {
        const radius = params.radius;
        const height = params.height;
        const segments = params.segments;

        const half_height = height / 2.0;

        // 计算顶点数和索引数
        const vertex_count = segments + 2; // 顶点+底面中心+底面边缘
        const index_count = segments * 3 + segments * 3; // 侧面三角形+底面三角形

        var vertices = try allocator.alloc(Vertex, vertex_count);
        var indices = try allocator.alloc(u16, index_count);

        // 生成顶点
        var i: u32 = 0;

        // 顶点
        vertices[i] = Vertex{ .position = [3]f32{ 0.0, half_height, 0.0 } };
        i += 1;

        // 底面中心
        vertices[i] = Vertex{ .position = [3]f32{ 0.0, -half_height, 0.0 } };
        i += 1;

        // 底面边缘顶点
        for (0..segments) |seg| {
            const angle = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments)) * 2.0 * std.math.pi;
            const x = radius * std.math.cos(angle);
            const z = radius * std.math.sin(angle);

            vertices[i] = Vertex{ .position = [3]f32{ x, -half_height, z } };
            i += 1;
        }

        // 生成索引
        i = 0;

        // 侧面三角形
        for (0..segments) |seg| {
            indices[i] = 0;
            indices[i + 1] = @as(u16, @intCast(2 + seg));
            indices[i + 2] = @as(u16, @intCast(2 + ((seg + 1) % segments)));
            i += 3;
        }

        // 底面三角形
        for (0..segments) |seg| {
            indices[i] = 1;
            indices[i + 1] = @as(u16, @intCast(2 + seg));
            indices[i + 2] = @as(u16, @intCast(2 + ((seg + 1) % segments)));
            i += 3;
        }

        return .{ .vertices = vertices, .indices = indices };
    }

    // 添加带参数的几何对象
    pub export fn addGeometryObjectWithParams(engine: *Engine, geometry_type: GeometryType, params: *const GeometryParams, vertex_shader_path: [*:0]const u8, pixel_shader_path: [*:0]const u8) void {
        const allocator = std.heap.page_allocator;
        // 由于export导出给了C ABI，所以这里的路径参数是[*:0]const u8，zig内部又需要转换为[]u8
        const vertex_path = std.mem.sliceTo(vertex_shader_path, 0);
        const pixel_path = std.mem.sliceTo(pixel_shader_path, 0);

        switch (geometry_type) {
            .Cube => {
                const cube_params = params.Cube;
                const geometry = generateCube(allocator, cube_params) catch |err| {
                    std.debug.print("Error generating cube: {}", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                engine.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path) catch |err| {
                    std.debug.print("Error adding cube: {}", .{err});
                };
            },
            .Sphere => {
                const sphere_params = params.Sphere;
                const geometry = generateSphere(allocator, sphere_params) catch |err| {
                    std.debug.print("Error generating sphere: {}", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                engine.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path) catch |err| {
                    std.debug.print("Error adding sphere: {}", .{err});
                };
            },
            .Cylinder => {
                const cylinder_params = params.Cylinder;
                const geometry = generateCylinder(allocator, cylinder_params) catch |err| {
                    std.debug.print("Error generating cylinder: {}", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                engine.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path) catch |err| {
                    std.debug.print("Error adding cylinder: {}", .{err});
                };
            },
            .Cone => {
                const cone_params = params.Cone;
                const geometry = generateCone(allocator, cone_params) catch |err| {
                    std.debug.print("Error generating cone: {}", .{err});
                    return;
                };
                defer {
                    allocator.free(geometry.vertices);
                    allocator.free(geometry.indices);
                }
                engine.addIndexedRenderObject(geometry.vertices, geometry.indices, vertex_path, pixel_path) catch |err| {
                    std.debug.print("Error adding cone: {}", .{err});
                };
            },
            else => {},
        }
    }
};
