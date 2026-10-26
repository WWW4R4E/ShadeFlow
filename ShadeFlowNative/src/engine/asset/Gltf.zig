//! glTF 2.0 网格解析器（本轮范围：只取几何，不含节点层级/变换、法线、UV、纹理）。
//!
//! 两层 API：
//! - `parseFromMemory`：纯内存解析（JSON 字节 + 已备好的 buffer 字节表），
//!   不碰文件系统，测试直接喂内嵌数据。
//! - `load`：文件入口，处理 `.gltf`（内嵌 base64 data URI / 外部 `.bin`）与
//!   `.glb` 二进制容器两种封装，把 buffer 备齐后转调 `parseFromMemory`。
//!
//! 属性支持：`POSITION`（必须，VEC3 f32）+ `COLOR_0`（可选，VEC3/VEC4 的
//! f32 或归一化 u8/u16）。缺 COLOR_0 时回退材质 `baseColorFactor`，再回退
//! 白色。多个 primitive 合并为单个索引网格（顶点拼接 + 索引偏移），引擎侧
//! 一个对象一次 draw。
//!
//! 坐标系：glTF 是 Y-up 右手系，引擎投影是 D3D 风格左手系——X 取反做
//! RH→LH 转换（真机验证过：不翻转模型会左右镜像）。cull 目前是 none，
//! 翻转带来的绕序变化无副作用；将来开背面剔除时要重新审计。

const std = @import("std");

const Types = @import("render_types");

/// 解析出的几何：引擎 `Vertex`（position + color）+ u32 索引。
pub const Geometry = struct {
    vertices: []Types.Vertex,
    indices: []u32,

    pub fn deinit(self: *Geometry, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
        self.vertices = &.{};
        self.indices = &.{};
    }
};

// =============================================================================
// JSON 场景描述（std.json，忽略未知字段——glTF 扩展字段直接放过）
// =============================================================================

const PbrMetallicRoughness = struct {
    baseColorFactor: ?[4]f32 = null,
};

const Material = struct {
    pbrMetallicRoughness: ?PbrMetallicRoughness = null,
};

const PrimitiveAttributes = struct {
    POSITION: ?i64 = null,
    COLOR_0: ?i64 = null,
};

const Primitive = struct {
    attributes: PrimitiveAttributes = .{},
    indices: ?i64 = null,
    material: ?i64 = null,
};

const Mesh = struct {
    primitives: []const Primitive = &.{},
};

/// glTF componentType 常量（spec 2.0）。
const component_type_i8: i64 = 5120;
const component_type_u8: i64 = 5121;
const component_type_i16: i64 = 5122;
const component_type_u16: i64 = 5123;
const component_type_u32: i64 = 5125;
const component_type_f32: i64 = 5126;

const Accessor = struct {
    bufferView: ?i64 = null,
    componentType: i64,
    count: i64,
    @"type": []const u8,
    byteOffset: i64 = 0,
    normalized: bool = false,
};

const BufferView = struct {
    buffer: i64,
    byteOffset: i64 = 0,
    byteLength: i64,
    byteStride: ?i64 = null,
};

const Buffer = struct {
    uri: ?[]const u8 = null,
    byteLength: i64 = 0,
};

const GltfJson = struct {
    asset: struct { version: []const u8 = "" } = .{},
    scenes: []const struct{ nodes: []const i64 = &.{} } = &.{},
    meshes: []const Mesh = &.{},
    accessors: []const Accessor = &.{},
    bufferViews: []const BufferView = &.{},
    buffers: []const Buffer = &.{},
    materials: []const Material = &.{},
};

// =============================================================================
// 纯内存解析
// =============================================================================

const ParseError = error{
    UnsupportedGltfVersion,
    UnsupportedComponentType,
    UnsupportedAccessorType,
    UnsupportedIndexComponentType,
    UnsupportedColorComponentType,
    MissingPositionAttribute,
    MissingBuffer,
    MissingBufferView,
    MissingIndices,
    AccessorWithoutBufferView,
    BufferTooSmall,
    EmptyMesh,
};

/// 从 JSON + buffer 字节表解析全部 mesh 的几何（多 primitive 合并）。
///
/// `buffers` 的生命周期只需覆盖本次调用；返回的 `Geometry` 由调用方
/// `deinit(allocator)` 释放。
pub fn parseFromMemory(
    allocator: std.mem.Allocator,
    json_bytes: []const u8,
    buffers: []const []const u8,
) (ParseError || std.json.ParseError(std.json.Scanner) || std.mem.Allocator.Error)!Geometry {
    var parsed = try std.json.parseFromSlice(GltfJson, allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const gltf = parsed.value;

    if (gltf.asset.version.len != 0 and !std.mem.startsWith(u8, gltf.asset.version, "2"))
        return error.UnsupportedGltfVersion;

    var vertices: std.ArrayList(Types.Vertex) = .empty;
    errdefer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    errdefer indices.deinit(allocator);

    for (gltf.meshes) |mesh| {
        for (mesh.primitives) |primitive| {
            const base_vertex: u32 = @intCast(vertices.items.len);

            // 颜色来源优先级：COLOR_0 > 材质 baseColorFactor > 白色。
            const fallback_color = fallbackColorOf(&gltf, &primitive);

            const position_acc = try accessorOf(&gltf, primitive.attributes.POSITION);
            if (!std.mem.eql(u8, position_acc.@"type", "VEC3") or position_acc.componentType != component_type_f32)
                return error.UnsupportedComponentType;

            const color_acc: ?*const Accessor = if (primitive.attributes.COLOR_0) |ci|
                try accessorOf(&gltf, ci)
            else
                null;

            const pos_view = try viewOf(&gltf, position_acc);
            const pos_bytes = try viewBytes(buffers, pos_view, position_acc.byteOffset, @intCast(position_acc.count * 12));

            const color_view: ?*const BufferView = if (color_acc) |ca| try viewOf(&gltf, ca) else null;
            const color_bytes: ?[]const u8 = if (color_acc != null)
                try viewBytes(buffers, color_view.?, color_acc.?.byteOffset, colorAccesorBytes(color_acc.?, @intCast(position_acc.count)))
            else
                null;

            const count: usize = @intCast(position_acc.count);
            try vertices.ensureUnusedCapacity(allocator, count);
            for (0..count) |i| {
                const pos: [3]f32 = @bitCast(pos_bytes[i * 12 ..][0..12].*);

                var color: [4]f32 = fallback_color;
                if (color_acc) |ca| {
                    const stride: i64 = @intCast(componentSize(ca) * vectorLength(ca));
                    color = readColor(ca, color_bytes.?[0 .. @intCast(ca.count * stride)], i);
                }

                vertices.appendAssumeCapacity(.{
                    // RH→LH：X 取反（见文件头坐标系说明）。
                    .position = .{ -pos[0], pos[1], pos[2] },
                    .color = color,
                });
            }

            // 索引：无索引 primitive 直接展开成 i=0..count。
            if (primitive.indices) |ii| {
                const index_acc = try accessorOf(&gltf, ii);
                if (!std.mem.eql(u8, index_acc.@"type", "SCALAR"))
                    return error.UnsupportedAccessorType;
                const index_view = try viewOf(&gltf, index_acc);
                const component_size: usize = indexComponentSize(index_acc.componentType) orelse return error.UnsupportedIndexComponentType;
                const needed: i64 = index_acc.count * @as(i64, @intCast(component_size));
                const index_bytes = try viewBytes(buffers, index_view, index_acc.byteOffset, @intCast(needed));

                try indices.ensureUnusedCapacity(allocator, @intCast(index_acc.count));
                for (0..@intCast(index_acc.count)) |i| {
                    const raw: u32 = switch (index_acc.componentType) {
                        component_type_u8 => index_bytes[i],
                        component_type_u16 => std.mem.readInt(u16, index_bytes[i * 2 ..][0..2], .little),
                        component_type_u32 => std.mem.readInt(u32, index_bytes[i * 4 ..][0..4], .little),
                        else => return error.UnsupportedIndexComponentType,
                    };
                    indices.appendAssumeCapacity(raw + base_vertex);
                }
            } else {
                try indices.ensureUnusedCapacity(allocator, count);
                for (0..count) |i| {
                    indices.appendAssumeCapacity(base_vertex + @as(u32, @intCast(i)));
                }
            }
        }
    }

    if (vertices.items.len == 0) return error.EmptyMesh;

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

// =============================================================================
// 文件入口
// =============================================================================

const glb_magic: u32 = 0x46546C67; // "glTF"
const chunk_json: u32 = 0x4E4F534A; // "JSON"
const chunk_bin: u32 = 0x004E4942; // "BIN\0"

/// 读入 `.gltf` / `.glb` 并解析。buffer 来源三选一：data URI（base64）、
/// `.gltf` 同目录的外部 `.bin`、`.glb` 的 BIN chunk。
pub fn load(allocator: std.mem.Allocator, path: []const u8) !Geometry {
    const io = std.Io.Threaded.global_single_threaded.io();
    const file_bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(file_bytes);

    if (file_bytes.len >= 12 and std.mem.readInt(u32, file_bytes[0..4], .little) == glb_magic) {
        return loadGlb(allocator, file_bytes);
    }
    return loadGltfJson(allocator, path, file_bytes);
}

fn loadGltfJson(allocator: std.mem.Allocator, path: []const u8, json_bytes: []const u8) !Geometry {
    var parsed = try std.json.parseFromSlice(GltfJson, allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const io = std.Io.Threaded.global_single_threaded.io();

    // data URI / 外部 .bin 都备齐成字节表，后面走统一的纯内存解析。
    var buffers: std.ArrayList([]const u8) = .empty;
    defer {
        for (buffers.items) |b| allocator.free(b);
        buffers.deinit(allocator);
    }

    const dir = std.fs.path.dirname(path) orelse ".";
    for (parsed.value.buffers) |buffer| {
        const uri = buffer.uri orelse return error.MissingBuffer;
        if (dataUriBase64(uri)) |b64| {
            const decoded = try decodeBase64(allocator, b64);
            try buffers.append(allocator, decoded);
        } else {
            const bin_path = try std.fs.path.join(allocator, &.{ dir, uri });
            defer allocator.free(bin_path);
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, bin_path, allocator, .limited(512 * 1024 * 1024));
            try buffers.append(allocator, bytes);
        }
    }

    return parseFromMemory(allocator, json_bytes, buffers.items);
}

fn loadGlb(allocator: std.mem.Allocator, bytes: []const u8) !Geometry {
    // 头：magic(4) version(4) total_length(4)；之后是 8 字节对齐的 chunk
    // 序列（length(4) type(4) data...）。
    const total_length = std.mem.readInt(u32, bytes[8..12], .little);
    if (total_length > bytes.len) return error.BufferTooSmall;

    var json_bytes: ?[]const u8 = null;
    var bin_bytes: ?[]const u8 = null;

    var offset: usize = 12;
    while (offset + 8 <= bytes.len) {
        const chunk_length = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        const chunk_type = std.mem.readInt(u32, bytes[offset + 4 ..][0..4], .little);
        offset += 8;
        if (offset + chunk_length > bytes.len) return error.BufferTooSmall;

        const data = bytes[offset .. offset + chunk_length];
        if (chunk_type == chunk_json) {
            json_bytes = data;
        } else if (chunk_type == chunk_bin) {
            bin_bytes = data;
        }
        offset += chunk_length;
        // chunk 之间 4 字节对齐（规范要求）。
        offset = std.mem.alignForward(usize, offset, 4);
    }

    const json = json_bytes orelse return error.MissingBuffer;

    var buffers: std.ArrayList([]const u8) = .empty;
    defer {
        for (buffers.items) |b| allocator.free(b);
        buffers.deinit(allocator);
    }

    var parsed = try std.json.parseFromSlice(GltfJson, allocator, json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    // GLB 的 buffer.uri 为空即指 BIN chunk；出现 data URI 的罕见情况也支持。
    for (parsed.value.buffers) |buffer| {
        if (buffer.uri) |uri| {
            if (dataUriBase64(uri)) |b64| {
                try buffers.append(allocator, try decodeBase64(allocator, b64));
                continue;
            }
        }
        if (bin_bytes) |bin| {
            try buffers.append(allocator, bin); // 指向 file_bytes 内部，不另拷贝
        } else {
            return error.MissingBuffer;
        }
    }

    return parseFromMemory(allocator, json, buffers.items);
}

// =============================================================================
// 内部
// =============================================================================

fn accessorOf(gltf: *const GltfJson, index_opt: ?i64) !*const Accessor {
    const index = index_opt orelse return error.MissingPositionAttribute;
    if (index < 0 or index >= @as(i64, @intCast(gltf.accessors.len))) return error.MissingBufferView;
    return &gltf.accessors[@intCast(index)];
}

fn viewOf(gltf: *const GltfJson, accessor: *const Accessor) !*const BufferView {
    const index = accessor.bufferView orelse return error.AccessorWithoutBufferView;
    if (index < 0 or index >= @as(i64, @intCast(gltf.bufferViews.len))) return error.MissingBufferView;
    return &gltf.bufferViews[@intCast(index)];
}

/// bufferView [+ accessor.byteOffset] 的越界检查 + 切片。
fn viewBytes(
    buffers: []const []const u8,
    view: *const BufferView,
    accessor_offset: i64,
    needed: usize,
) ![]const u8 {
    if (view.buffer < 0 or view.buffer >= @as(i64, @intCast(buffers.len))) return error.MissingBuffer;
    const data = buffers[@intCast(view.buffer)];
    const start: usize = @intCast(view.byteOffset + accessor_offset);
    if (start + needed > data.len) return error.BufferTooSmall;
    return data[start .. start + needed];
}

fn fallbackColorOf(gltf: *const GltfJson, primitive: *const Primitive) [4]f32 {
    if (primitive.material) |mi| {
        if (mi >= 0 and mi < @as(i64, @intCast(gltf.materials.len))) {
            if (gltf.materials[@intCast(mi)].pbrMetallicRoughness) |pbr| {
                if (pbr.baseColorFactor) |c| return c;
            }
        }
    }
    return .{ 1.0, 1.0, 1.0, 1.0 };
}

fn vectorLength(accessor: *const Accessor) usize {
    if (std.mem.eql(u8, accessor.@"type", "SCALAR")) return 1;
    if (std.mem.eql(u8, accessor.@"type", "VEC2")) return 2;
    if (std.mem.eql(u8, accessor.@"type", "VEC3")) return 3;
    if (std.mem.eql(u8, accessor.@"type", "VEC4")) return 4;
    return 0;
}

fn componentSize(accessor: *const Accessor) usize {
    return switch (accessor.componentType) {
        component_type_i8, component_type_u8 => 1,
        component_type_i16, component_type_u16 => 2,
        component_type_u32, component_type_f32 => 4,
        else => 0,
    };
}

fn indexComponentSize(component_type: i64) ?usize {
    return switch (component_type) {
        component_type_u8 => 1,
        component_type_u16 => 2,
        component_type_u32 => 4,
        else => null,
    };
}

/// COLOR_0 一行的字节跨度（紧凑布局假设：stride = 组件大小 × 向量长度）。
fn colorAccesorBytes(accessor: *const Accessor, count: usize) usize {
    return count * componentSize(accessor) * vectorLength(accessor);
}

fn readColor(accessor: *const Accessor, bytes: []const u8, index: usize) [4]f32 {
    const len = vectorLength(accessor);
    const size = componentSize(accessor);
    const row = bytes[index * len * size ..][0 .. len * size];

    var rgb: [3]f32 = .{ 1, 1, 1 };
    var alpha: f32 = 1.0;

    for (0..@min(len, 4)) |c| {
        const value: f32 = switch (accessor.componentType) {
            component_type_f32 => @bitCast(std.mem.readInt(u32, row[c * 4 ..][0..4], .little)),
            component_type_u16 => blk: {
                const raw = std.mem.readInt(u16, row[c * 2 ..][0..2], .little);
                const v: f32 = @floatFromInt(raw);
                break :blk if (accessor.normalized) v / 65535.0 else v;
            },
            component_type_u8 => blk: {
                const v: f32 = @floatFromInt(row[c]);
                break :blk if (accessor.normalized) v / 255.0 else v;
            },
            else => 1.0,
        };
        if (c < 3) rgb[c] = value else alpha = value;
    }

    return .{ rgb[0], rgb[1], rgb[2], alpha };
}

/// `data:application/octet-stream;base64,XXXX` → base64 段；不是 data URI 返回 null。
fn dataUriBase64(uri: []const u8) ?[]const u8 {
    const prefix = "data:application/octet-stream;base64,";
    if (!std.mem.startsWith(u8, uri, prefix)) return null;
    return uri[prefix.len..];
}

fn decodeBase64(allocator: std.mem.Allocator, b64: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const size = try decoder.calcSizeForSlice(b64);
    const out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    try decoder.decode(out, b64);
    return out;
}

// =============================================================================
// 测试
// =============================================================================

const testing = std.testing;

/// 构造一个双 primitive 的最小 glTF JSON：p0 红 + 显式 COLOR_0（VEC4 f32），
/// p1 蓝走材质 baseColorFactor 回退。索引分别是 u16 / u32，顺带覆盖两种
/// componentType。
const test_json =
    \\{
    \\  "asset": {"version": "2.0"},
    \\  "scenes": [{"nodes": [0]}],
    \\  "nodes": [{"mesh": 0}],
    \\  "meshes": [{
    \\    "primitives": [
    \\      {
    \\        "attributes": {"POSITION": 0, "COLOR_0": 1},
    \\        "indices": 2,
    \\        "material": 0
    \\      },
    \\      {
    \\        "attributes": {"POSITION": 3},
    \\        "indices": 4,
    \\        "material": 1
    \\      }
    \\    ]
    \\  }],
    \\  "materials": [
    \\    {"pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.5, 0.5, 1.0]}},
    \\    {"pbrMetallicRoughness": {"baseColorFactor": [0.1, 0.2, 0.3, 1.0]}}
    \\  ],
    \\  "accessors": [
    \\    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
    \\    {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC4"},
    \\    {"bufferView": 2, "componentType": 5123, "count": 3, "type": "SCALAR"},
    \\    {"bufferView": 0, "componentType": 5126, "count": 2, "type": "VEC3", "byteOffset": 36},
    \\    {"bufferView": 3, "componentType": 5125, "count": 4, "type": "SCALAR"}
    \\  ],
    \\  "bufferViews": [
    \\    {"buffer": 0, "byteOffset": 0,  "byteLength": 60},
    \\    {"buffer": 0, "byteOffset": 60, "byteLength": 48},
    \\    {"buffer": 0, "byteOffset": 108, "byteLength": 6},
    \\    {"buffer": 0, "byteOffset": 114, "byteLength": 16}
    \\  ],
    \\  "buffers": [{
    \\    "uri": "data:application/octet-stream;base64,AAADAADABQ==",
    \\    "byteLength": 130
    \\  }]
    \\}
;

fn testBuffers(allocator: std.mem.Allocator) ![]u8 {
    // 手工组 buffer，布局与 JSON 里的 bufferViews 一致：
    //   [0..36)   p0 位置 ×3（accessor0，view0 byteOffset 0）
    //   [36..60)  p1 位置 ×2（accessor3，view0 byteOffset 36）
    //   [60..108) COLOR_0 ×3（accessor1，view1）
    //   [108..114) u16 索引 ×3（accessor2，view2）
    //   [114..130) u32 索引 ×4（accessor4，view3）
    const bytes = try allocator.alloc(u8, 130);
    @memset(bytes, 0);

    const p0 = [_]f32{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    @memcpy(bytes[0..36], std.mem.sliceAsBytes(&p0));
    const p1 = [_]f32{ 0, 0, 1, 1, 1, 1 };
    @memcpy(bytes[36..60], std.mem.sliceAsBytes(&p1));
    const c0 = [_]f32{ 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1 };
    @memcpy(bytes[60..108], std.mem.sliceAsBytes(&c0));
    std.mem.writeInt(u16, bytes[108..110], 0, .little);
    std.mem.writeInt(u16, bytes[110..112], 2, .little);
    std.mem.writeInt(u16, bytes[112..114], 1, .little);
    std.mem.writeInt(u32, bytes[114..118], 0, .little);
    std.mem.writeInt(u32, bytes[118..122], 1, .little);
    std.mem.writeInt(u32, bytes[122..126], 3, .little);
    std.mem.writeInt(u32, bytes[126..130], 2, .little);

    return bytes;
}

test "parseFromMemory: 双 primitive 合并、颜色回退与索引偏移" {
    var allocator_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer allocator_state.deinit();
    const allocator = allocator_state.allocator();

    const buffer = try testBuffers(allocator);
    var geometry = try parseFromMemory(allocator, test_json, &.{buffer});
    defer geometry.deinit(allocator);

    // 3 + 2 个顶点，3 + 4 个索引。
    try testing.expectEqual(@as(usize, 5), geometry.vertices.len);
    try testing.expectEqual(@as(usize, 7), geometry.indices.len);

    // p0 显式 COLOR_0。
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, geometry.vertices[0].color);
    // p1 无 COLOR_0 → 材质 baseColorFactor 回退。
    try testing.expectEqual([4]f32{ 0.1, 0.2, 0.3, 1.0 }, geometry.vertices[3].color);

    // p1 索引带 base_vertex 偏移：0,1,3,2 → 3,4,6,5。
    try testing.expectEqual(@as(u32, 3), geometry.indices[3]);
    try testing.expectEqual(@as(u32, 6), geometry.indices[5]);
    try testing.expectEqual(@as(u32, 5), geometry.indices[6]);
}

test "load: 仓库样例 SampleBox.gltf（双 primitive 合并）" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // zig build test 的 cwd 是构建根；文件不在就跳过（不当作失败）。
    var geometry = load(allocator, "assets/models/SampleBox.gltf") catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer geometry.deinit(allocator);

    // 两个 cube：16 顶点、72 索引。
    try testing.expectEqual(@as(usize, 16), geometry.vertices.len);
    try testing.expectEqual(@as(usize, 72), geometry.indices.len);
    // 两个 primitive 分别取到材质红/蓝（无 COLOR_0 回退路径）。
    try testing.expectApproxEqAbs(@as(f32, 0.95), geometry.vertices[0].color[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.95), geometry.vertices[8].color[2], 0.001);

    // 合并后的索引：p1 从 base_vertex=8 起，且全部落在顶点范围内。
    // （曾因样例数据预加了偏移导致索引 16..23 越界、蓝色 cube 不渲染。）
    try testing.expectEqual(@as(u32, 8), geometry.indices[36]);
    for (geometry.indices) |i| try testing.expect(i < 16);
}
