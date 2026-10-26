//! glTF 2.0 网格解析器（几何 + baseColorTexture；不含节点层级/变换、法线、
//! 光照类纹理）。
//!
//! 两层 API：
//! - `parseFromMemory`：纯内存解析（JSON 字节 + buffer 字节表 + 图片字节表），
//!   不碰文件系统，测试直接喂内嵌数据。
//! - `load`：文件入口，处理 `.gltf`（内嵌 base64 data URI / 外部文件）与
//!   `.glb` 二进制容器两种封装，把 buffer/image 字节备齐后转调
//!   `parseFromMemory`。
//!
//! 结构：**每个 primitive 一个 `Part`**（同材质合并的优化以后再说不迟）。
//! 有 `baseColorTexture` 的 part 走 `vertices_tex`（POSITION+TEXCOORD）+
//! `image`（图片原始编码字节，Engine 用 zigimg 解码后建 GPU 纹理）；没有的
//! 走 `vertices`（POSITION+COLOR_0 > 材质 baseColorFactor > 白色）。
//!
//! 坐标系：glTF 是 Y-up 右手系，引擎投影是 D3D 风格左手系——X 取反做
//! RH→LH 转换（真机验证过：不翻转模型会左右镜像）。UV 原点约定两边一致
//! （左上），透传。cull 目前是 none，翻转带来的绕序变化无副作用。

const std = @import("std");

const Types = @import("render_types");

/// 单个渲染单元 = 一个 primitive。`vertices`/`vertices_tex` 二选一：
/// 有 `image`（baseColorTexture）走后者。
pub const Part = struct {
    vertices: []Types.Vertex = &.{},
    vertices_tex: []Types.VertexTex = &.{},
    indices: []u32,
    /// 图片原始编码字节（PNG/JPEG，指向 `images[]` 的解码前内容）。
    image: ?[]u8 = null,

    pub fn deinit(self: *Part, allocator: std.mem.Allocator) void {
        if (self.vertices.len != 0) allocator.free(self.vertices);
        if (self.vertices_tex.len != 0) allocator.free(self.vertices_tex);
        allocator.free(self.indices);
        if (self.image) |img| allocator.free(img);
        self.vertices = &.{};
        self.vertices_tex = &.{};
        self.indices = &.{};
        self.image = null;
    }
};

/// 解析结果：全部 mesh 的 part 列表。
pub const Scene = struct {
    parts: []Part,

    pub fn deinit(self: *Scene, allocator: std.mem.Allocator) void {
        for (self.parts) |*part| part.deinit(allocator);
        allocator.free(self.parts);
        self.parts = &.{};
    }
};

// =============================================================================
// JSON 场景描述（std.json，忽略未知字段——glTF 扩展字段直接放过）
// =============================================================================

const TextureInfo = struct {
    index: i64,
    texCoord: ?i64 = null,
};

const PbrMetallicRoughness = struct {
    baseColorFactor: ?[4]f32 = null,
    baseColorTexture: ?TextureInfo = null,
};

const Material = struct {
    pbrMetallicRoughness: ?PbrMetallicRoughness = null,
};

const PrimitiveAttributes = struct {
    POSITION: ?i64 = null,
    COLOR_0: ?i64 = null,
    TEXCOORD_0: ?i64 = null,
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

const Texture = struct {
    source: ?i64 = null,
};

/// 图片来源三选一：uri（外部文件 / data URI）、GLB 内嵌（bufferView）。
const Image = struct {
    uri: ?[]const u8 = null,
    bufferView: ?i64 = null,
    mimeType: ?[]const u8 = null,
};

const GltfJson = struct {
    asset: struct { version: []const u8 = "" } = .{},
    scenes: []const struct{ nodes: []const i64 = &.{} } = &.{},
    meshes: []const Mesh = &.{},
    accessors: []const Accessor = &.{},
    bufferViews: []const BufferView = &.{},
    buffers: []const Buffer = &.{},
    materials: []const Material = &.{},
    textures: []const Texture = &.{},
    images: []const Image = &.{},
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
    MissingTexCoord,
    MissingBuffer,
    MissingBufferView,
    MissingIndices,
    AccessorWithoutBufferView,
    BufferTooSmall,
    EmptyMesh,
};

/// 从 JSON + buffer/image 字节表解析全部 mesh。
///
/// `buffers`/`images` 的生命周期只需覆盖本次调用；返回的 `Scene` 由调用方
/// `deinit(allocator)` 释放。
pub fn parseFromMemory(
    allocator: std.mem.Allocator,
    json_bytes: []const u8,
    buffers: []const []const u8,
    images: []const []const u8,
) (ParseError || std.json.ParseError(std.json.Scanner) || std.mem.Allocator.Error)!Scene {
    var parsed = try std.json.parseFromSlice(GltfJson, allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const gltf = parsed.value;

    if (gltf.asset.version.len != 0 and !std.mem.startsWith(u8, gltf.asset.version, "2"))
        return error.UnsupportedGltfVersion;

    var parts: std.ArrayList(Part) = .empty;
    errdefer {
        for (parts.items) |*part| part.deinit(allocator);
        parts.deinit(allocator);
    }

    for (gltf.meshes) |mesh| {
        for (mesh.primitives) |primitive| {
            // baseColorTexture：材质 → texture → source image 字节。
            const image_index = baseColorImageIndex(&gltf, &primitive);
            const textured = if (image_index) |ii|
                ii < images.len and images[ii].len != 0
            else
                false;

            const position_acc = try accessorOf(&gltf, primitive.attributes.POSITION);
            if (!std.mem.eql(u8, position_acc.@"type", "VEC3") or position_acc.componentType != component_type_f32)
                return error.UnsupportedComponentType;

            const count: usize = @intCast(position_acc.count);
            const pos_view = try viewOf(&gltf, position_acc);
            const pos_bytes = try viewBytes(buffers, pos_view, position_acc.byteOffset, @intCast(position_acc.count * 12));

            var part = Part{ .indices = &.{} };

            if (textured) {
                // ---- 带纹理路径：POSITION + TEXCOORD_0，图片字节挂到 part ----
                const uv_acc: *const Accessor = blk: {
                    if (primitive.attributes.TEXCOORD_0) |ti| break :blk try accessorOf(&gltf, ti);
                    return error.MissingTexCoord;
                };
                if (!std.mem.eql(u8, uv_acc.@"type", "VEC2"))
                    return error.UnsupportedAccessorType;
                if (uv_acc.count != position_acc.count)
                    return error.BufferTooSmall;

                const uv_view = try viewOf(&gltf, uv_acc);
                const uv_stride_bytes: usize = componentSize(uv_acc) * 2;
                const uv_needed: i64 = uv_acc.count * @as(i64, @intCast(uv_stride_bytes));
                const uv_bytes = try viewBytes(buffers, uv_view, uv_acc.byteOffset, @intCast(uv_needed));

                var vertices_tex = try allocator.alloc(Types.VertexTex, count);
                errdefer allocator.free(vertices_tex);
                for (0..count) |i| {
                    const pos: [3]f32 = @bitCast(pos_bytes[i * 12 ..][0..12].*);
                    vertices_tex[i] = .{
                        // RH→LH：X 取反（见文件头坐标系说明）。
                        .position = .{ -pos[0], pos[1], pos[2] },
                        .uv = readUV(uv_acc, uv_bytes, i),
                    };
                }
                part.vertices_tex = vertices_tex;

                const ii: usize = @intCast(image_index.?);
                part.image = try allocator.dupe(u8, images[ii]);
            } else {
                // ---- 无纹理路径：POSITION +（COLOR_0 > 材质色 > 白）----
                const fallback_color = fallbackColorOf(&gltf, &primitive);
                const color_acc: ?*const Accessor = if (primitive.attributes.COLOR_0) |ci|
                    try accessorOf(&gltf, ci)
                else
                    null;

                const color_view: ?*const BufferView = if (color_acc) |ca| try viewOf(&gltf, ca) else null;
                const color_bytes: ?[]const u8 = if (color_acc != null)
                    try viewBytes(buffers, color_view.?, color_acc.?.byteOffset, colorAccesorBytes(color_acc.?, @intCast(position_acc.count)))
                else
                    null;

                var vertices = try allocator.alloc(Types.Vertex, count);
                errdefer allocator.free(vertices);
                for (0..count) |i| {
                    const pos: [3]f32 = @bitCast(pos_bytes[i * 12 ..][0..12].*);

                    var color: [4]f32 = fallback_color;
                    if (color_acc) |ca| {
                        const stride: i64 = @intCast(componentSize(ca) * vectorLength(ca));
                        color = readColor(ca, color_bytes.?[0 .. @intCast(ca.count * stride)], i);
                    }

                    vertices[i] = .{
                        // RH→LH：X 取反（见文件头坐标系说明）。
                        .position = .{ -pos[0], pos[1], pos[2] },
                        .color = color,
                    };
                }
                part.vertices = vertices;
            }

            // 索引（part 内局部编号；无索引 primitive 展开成 i=0..count）。
            const index_total: usize = if (primitive.indices) |ii| @intCast(try indexCount(&gltf, ii)) else count;
            var indices = try allocator.alloc(u32, index_total);
            errdefer allocator.free(indices);

            if (primitive.indices) |ii| {
                const index_acc = try accessorOf(&gltf, ii);
                if (!std.mem.eql(u8, index_acc.@"type", "SCALAR"))
                    return error.UnsupportedAccessorType;
                const index_view = try viewOf(&gltf, index_acc);
                const component_size: usize = indexComponentSize(index_acc.componentType) orelse return error.UnsupportedIndexComponentType;
                const needed: i64 = index_acc.count * @as(i64, @intCast(component_size));
                const index_bytes = try viewBytes(buffers, index_view, index_acc.byteOffset, @intCast(needed));

                for (0..@intCast(index_acc.count)) |i| {
                    indices[i] = switch (index_acc.componentType) {
                        component_type_u8 => index_bytes[i],
                        component_type_u16 => std.mem.readInt(u16, index_bytes[i * 2 ..][0..2], .little),
                        component_type_u32 => std.mem.readInt(u32, index_bytes[i * 4 ..][0..4], .little),
                        else => return error.UnsupportedIndexComponentType,
                    };
                }
            } else {
                for (0..count) |i| {
                    indices[i] = @intCast(i);
                }
            }
            part.indices = indices;

            try parts.append(allocator, part);
        }
    }

    if (parts.items.len == 0) return error.EmptyMesh;

    return .{ .parts = try parts.toOwnedSlice(allocator) };
}

/// baseColorTexture → image 下标；没有贴图返回 null。
fn baseColorImageIndex(gltf: *const GltfJson, primitive: *const Primitive) ?usize {
    const material_index = primitive.material orelse return null;
    if (material_index < 0 or material_index >= @as(i64, @intCast(gltf.materials.len))) return null;
    const pbr = gltf.materials[@intCast(material_index)].pbrMetallicRoughness orelse return null;
    const tex_info = pbr.baseColorTexture orelse return null;
    if (tex_info.texCoord) |tc| {
        if (tc != 0) return null; // 多套 UV 不支持，按无贴图处理
    }
    const tex_index = tex_info.index;
    if (tex_index < 0 or tex_index >= @as(i64, @intCast(gltf.textures.len))) return null;
    const source = gltf.textures[@intCast(tex_index)].source orelse return null;
    if (source < 0) return null;
    return @intCast(source);
}

/// 读一行 UV（VEC2；f32 或归一化 u8/u16）。
fn readUV(accessor: *const Accessor, bytes: []const u8, index: usize) [2]f32 {
    const size = componentSize(accessor);
    const row = bytes[index * 2 * size ..][0 .. 2 * size];
    if (accessor.componentType == component_type_f32) {
        const u: f32 = @bitCast(std.mem.readInt(u32, row[0..4], .little));
        const v: f32 = @bitCast(std.mem.readInt(u32, row[4..8], .little));
        return .{ u, v };
    }
    var uv: [2]f32 = .{ 0, 0 };
    inline for (0..2) |c| {
        uv[c] = switch (accessor.componentType) {
            component_type_u16 => blk: {
                const raw = std.mem.readInt(u16, row[c * 2 ..][0..2], .little);
                const v: f32 = @floatFromInt(raw);
                break :blk if (accessor.normalized) v / 65535.0 else v;
            },
            component_type_u8 => blk: {
                const v: f32 = @floatFromInt(row[c]);
                break :blk if (accessor.normalized) v / 255.0 else v;
            },
            else => 0.0,
        };
    }
    return uv;
}

fn indexCount(gltf: *const GltfJson, index: i64) !i64 {
    const acc = try accessorOf(gltf, index);
    return acc.count;
}

// =============================================================================
// 文件入口
// =============================================================================

const glb_magic: u32 = 0x46546C67; // "glTF"
const chunk_json: u32 = 0x4E4F534A; // "JSON"
const chunk_bin: u32 = 0x004E4942; // "BIN\0"

/// 读入 `.gltf` / `.glb` 并解析。buffer 来源三选一：data URI（base64）、
/// `.gltf` 同目录的外部文件、`.glb` 的 BIN chunk；图片同（外部文件 /
/// data URI / GLB bufferView）。
pub fn load(allocator: std.mem.Allocator, path: []const u8) !Scene {
    const io = std.Io.Threaded.global_single_threaded.io();
    const file_bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(file_bytes);

    if (file_bytes.len >= 12 and std.mem.readInt(u32, file_bytes[0..4], .little) == glb_magic) {
        return loadGlb(allocator, file_bytes);
    }
    return loadGltfJson(allocator, path, file_bytes);
}

fn loadGltfJson(allocator: std.mem.Allocator, path: []const u8, json_bytes: []const u8) !Scene {
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

    // 图片字节表：外部文件 / data URI。
    var images: std.ArrayList([]const u8) = .empty;
    defer {
        for (images.items) |b| allocator.free(b);
        images.deinit(allocator);
    }
    for (parsed.value.images) |image| {
        if (image.uri) |uri| {
            if (dataUriBase64(uri)) |b64| {
                try images.append(allocator, try decodeBase64(allocator, b64));
            } else {
                const img_path = try std.fs.path.join(allocator, &.{ dir, uri });
                defer allocator.free(img_path);
                try images.append(allocator, try std.Io.Dir.cwd().readFileAlloc(io, img_path, allocator, .limited(256 * 1024 * 1024)));
            }
        } else {
            try images.append(allocator, ""); // 无来源的 image 按缺失处理
        }
    }

    return parseFromMemory(allocator, json_bytes, buffers.items, images.items);
}

fn loadGlb(allocator: std.mem.Allocator, bytes: []const u8) !Scene {
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

    // 图片字节表：bufferView 内嵌 / data URI / 外部文件。
    var images: std.ArrayList([]const u8) = .empty;
    defer {
        for (images.items) |b| allocator.free(b);
        images.deinit(allocator);
    }
    for (parsed.value.images) |image| {
        if (image.bufferView) |bvi| {
            if (bvi < 0 or bvi >= @as(i64, @intCast(parsed.value.bufferViews.len)))
                return error.MissingBuffer;
            const view = parsed.value.bufferViews[@intCast(bvi)];
            const data = buffers.items[@intCast(view.buffer)];
            const start: usize = @intCast(view.byteOffset);
            if (start + @as(usize, @intCast(view.byteLength)) > data.len) return error.BufferTooSmall;
            // images 表统一拥有自己的内存（defer 里统一 free），这里 dupe 一份。
            try images.append(allocator, try allocator.dupe(u8, data[start .. start + @as(usize, @intCast(view.byteLength))]));
        } else if (image.uri) |uri| {
            if (dataUriBase64(uri)) |b64| {
                try images.append(allocator, try decodeBase64(allocator, b64));
            } else {
                try images.append(allocator, ""); // GLB 里不允许外部文件，按缺失处理
            }
        } else {
            try images.append(allocator, "");
        }
    }

    return parseFromMemory(allocator, json, buffers.items, images.items);
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

test "parseFromMemory: 双 primitive 拆 Part、颜色回退与局部索引" {
    var allocator_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer allocator_state.deinit();
    const allocator = allocator_state.allocator();

    const buffer = try testBuffers(allocator);
    var scene = try parseFromMemory(allocator, test_json, &.{buffer}, &.{});
    defer scene.deinit(allocator);

    // 每个 primitive 一个 part：3 顶点 + 2 顶点。
    try testing.expectEqual(@as(usize, 2), scene.parts.len);
    try testing.expectEqual(@as(usize, 3), scene.parts[0].vertices.len);
    try testing.expectEqual(@as(usize, 2), scene.parts[1].vertices.len);

    // p0 显式 COLOR_0；p1 无 COLOR_0 → 材质 baseColorFactor 回退。
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, scene.parts[0].vertices[0].color);
    try testing.expectEqual([4]f32{ 0.1, 0.2, 0.3, 1.0 }, scene.parts[1].vertices[0].color);

    // 索引是 part 内局部编号：0,2,1 / 0,1,3,2。
    try testing.expectEqual(@as(u32, 0), scene.parts[0].indices[0]);
    try testing.expectEqual(@as(u32, 1), scene.parts[0].indices[2]);
    try testing.expectEqual(@as(u32, 3), scene.parts[1].indices[2]);
}

test "parseFromMemory: baseColorTexture → 带纹理 Part" {
    var allocator_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer allocator_state.deinit();
    const allocator = allocator_state.allocator();

    // 1x1 PNG（数据 URI 之外直接给字节表）。
    const tiny_png = [_]u8{
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    };

    const json =
        \\{
        \\  "asset": {"version": "2.0"},
        \\  "meshes": [{"primitives": [{
        \\    "attributes": {"POSITION": 0, "TEXCOORD_0": 1},
        \\    "indices": 2,
        \\    "material": 0
        \\  }]}],
        \\  "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
        \\  "textures": [{"source": 0}],
        \\  "images": [{"bufferView": 1, "mimeType": "image/png"}],
        \\  "accessors": [
        \\    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
        \\    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC2", "byteOffset": 36},
        \\    {"bufferView": 0, "componentType": 5123, "count": 3, "type": "SCALAR", "byteOffset": 60}
        \\  ],
        \\  "bufferViews": [
        \\    {"buffer": 0, "byteOffset": 0, "byteLength": 66}
        \\  ],
        \\  "buffers": [{"byteLength": 66}]
        \\}
    ;

    // buffer：3 位置(36B) + 3 UV(24B) + 3 u16 索引(6B) = 66B。
    const buffer = try allocator.alloc(u8, 66);
    @memset(buffer, 0);
    std.mem.writeInt(u16, buffer[60..62], 0, .little);
    std.mem.writeInt(u16, buffer[62..64], 1, .little);
    std.mem.writeInt(u16, buffer[64..66], 2, .little);

    var scene = try parseFromMemory(allocator, json, &.{buffer}, &.{&tiny_png});
    defer scene.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), scene.parts.len);
    const part = &scene.parts[0];
    try testing.expectEqual(@as(usize, 3), part.vertices_tex.len);
    try testing.expectEqual(@as(usize, 0), part.vertices.len);
    try testing.expect(part.image != null);
    try testing.expectEqualSlices(u8, &tiny_png, part.image.?);
    // RH→LH：位置 X 取反。
    try testing.expectEqual(@as(f32, -0.0), part.vertices_tex[0].position[0]);
}

test "load: 仓库样例 SampleBox.gltf（双 primitive 拆 Part）" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // zig build test 的 cwd 是构建根；文件不在就跳过（不当作失败）。
    var scene = load(allocator, "assets/models/SampleBox.gltf") catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer scene.deinit(allocator);

    // 每个 cube 一个 part：8 顶点、36 索引。
    try testing.expectEqual(@as(usize, 2), scene.parts.len);
    try testing.expectEqual(@as(usize, 8), scene.parts[0].vertices.len);
    try testing.expectEqual(@as(usize, 36), scene.parts[0].indices.len);
    // 两个 part 分别取到材质红/蓝（无 COLOR_0 回退路径）。
    try testing.expectApproxEqAbs(@as(f32, 0.95), scene.parts[0].vertices[0].color[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.95), scene.parts[1].vertices[0].color[2], 0.001);

    // 索引是 part 内局部编号且全部落在顶点范围内。
    // （曾因样例数据预加了偏移导致索引 8..15 越界、蓝色 cube 不渲染。）
    for (scene.parts[1].indices) |i| try testing.expect(i < 8);
}
