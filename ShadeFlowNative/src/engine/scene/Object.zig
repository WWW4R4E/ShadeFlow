const Buffer = @import("../render/d3d11/Buffer.zig").Buffer;
const Shader = @import("../render/d3d11/Shader.zig").Shader;
const Transform = @import("Transform.zig").Transform;

// 基础渲染对象，包含所有可渲染物体的共同属性
pub const Object = struct {
    vertex_buffer: Buffer,
    shader: Shader,
    transform: Transform = Transform{},
    is_select: bool = false,

    pub fn select(self: *Object, is_select: bool) void {
        self.is_select = is_select;
        if (is_select) {}
    }

    pub fn deinit(self: *Object) void {
        self.vertex_buffer.deinit();
        self.shader.deinit();
    }
};

// 普通渲染对象（顶点绘制）
pub const RenderObject = struct {
    object: Object,

    pub fn update(self: *RenderObject, delta_time: f64) void {
        self.object.transform.update(delta_time);
    }

    pub fn deinit(self: *RenderObject) void {
        self.object.deinit();
    }
};

// 索引渲染对象（索引绘制）
pub const IndexedRenderObject = struct {
    object: Object,
    index_buffer: Buffer,
    index_count: u32,

    pub fn update(self: *IndexedRenderObject, delta_time: f64) void {
        self.object.transform.update(delta_time);
    }

    pub fn deinit(self: *IndexedRenderObject) void {
        self.object.deinit();
        self.index_buffer.deinit();
    }
};
