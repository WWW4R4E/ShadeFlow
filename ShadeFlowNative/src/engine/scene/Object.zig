const std = @import("std");
const Buffer = @import("../render/Renderer.zig").Buffer;
const Shader = @import("../render/Renderer.zig").Shader;
const Pipeline = @import("../render/Renderer.zig").Pipeline;
const Transform = @import("Transform.zig").Transform;
const Aabb = @import("../math/Aabb.zig").Aabb;

// 基础渲染对象，包含所有可渲染物体的共同属性
pub const Object = struct {
    vertex_buffer: Buffer,
    /// 着色器程序（堆分配，这里持指针）。Pipeline 借用这个堆地址——如果按值
    /// 内嵌，append 进 ArrayList 拷贝/扩容挪动后，pipeline.shader 会指向旧
    /// 位置，退出析构时就是悬垂指针（vulkan 侧曾表现为退出时
    /// vkDestroyPipeline 崩溃）。析构顺序：pipeline 先于 shader。
    shader: *Shader,
    /// 管线：着色器 × 状态在创建时定型（D3D12=PSO，Vulkan=VkPipeline）。
    pipeline: Pipeline,
    transform: Transform = Transform{},
    // 顶点位置在局部空间的包围盒，创建时由顶点数据算出；拾取时把射线
    // 反变换到局部空间再和它做相交测试，所以旋转/缩放不需要重建。
    local_aabb: Aabb,
    is_select: bool = false,

    pub fn select(self: *Object, is_select: bool) void {
        self.is_select = is_select;
        if (is_select) {}
    }

    pub fn deinit(self: *Object) void {
        self.pipeline.deinit();
        self.vertex_buffer.deinit();
        self.shader.deinit();
        std.heap.page_allocator.destroy(self.shader);
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
