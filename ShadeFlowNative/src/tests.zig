//! `zig build test` 的根模块。
//!
//! Zig 只收集**在 test 块里显式引用过**的文件里的测试——单纯的 import 传递
//! 不会把测试带进来（`std/std.zig` 用 `testing.refAllDecls(@This())` 也是
//! 这个原因）。所以每个带测试的文件都要在这里列出来。
//!
//! 新增测试文件时记得同步加一行，否则它的用例会静默不跑。

test {
    // 宿主侧：输入状态（纯逻辑，不开窗口）
    _ = @import("host/Input.zig");

    // 引擎侧：纯数学部分
    _ = @import("engine/math/Aabb.zig");
    _ = @import("engine/math/Matrix.zig");
    _ = @import("engine/view/Picker.zig");
}
