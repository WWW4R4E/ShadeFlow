# 命名规范

参考 Zig 官方风格指南：<https://course.ziglang.cc/llms/engineering/style_guide.md>
（上游原文：<https://ziglang.org/documentation/master/#Style-Guide>）

官方指南不是强制的，但它给出的分类方式足够清晰；下面先写通用规则，再列出
本项目有意保留的内部约定。遇到冲突时，**以本文「项目内部约定」一节为准**。

## 文件与目录命名

Zig 文件按它声明的内容分两类：

| 元素                              | 风格       | 示例                                      |
| --------------------------------- | ---------- | ----------------------------------------- |
| **声明类型且带字段的文件**        | TitleCase  | `SwapChain.zig`、`Renderer.zig`           |
| **命名空间 / 纯函数 / 常量集合**  | snake_case | `mod.zig`、`root.zig`、`capi.zig`         |
| **目录**                          | snake_case | `render/backend/d3d12/`                   |

判断方法：文件里有没有一个带字段的 `struct` / `enum` / `union` 作为主体类型。
有就用 TitleCase（文件名与类型名一致）；没有就是命名空间文件，用 snake_case。

第三方或生成的文件（`vendor/vk.xml`、`zig-pkg/` 里的库等）保持原名，不套用本规范。

## 代码内命名

| 元素                                          | 风格       | 示例                                      |
| --------------------------------------------- | ---------- | ----------------------------------------- |
| **类型声明**（struct / enum / union / opaque）| TitleCase  | `SwapChain`、`NativeWindow`               |
| **作为命名空间的 0 字段 struct**              | snake_case | `const state = struct {};`                |
| **可调用且返回类型**（类型函数）              | TitleCase  | `ListTemplateFunction`、`ShortList`       |
| **可调用且返回非类型**（普通函数）            | camelCase  | `initHeap`、`parseArgs`、`functionName`   |
| **变量、参数、字段、常量、全局变量**          | snake_case | `buffer_len`、`file_name`                 |
| **类型别名**（给一个类型起名字）              | TitleCase  | `StructAlias`、`MyList`                   |
| **命名空间**                                  | snake_case | `render_types`、`state`                   |

关键判断依据是**「能不能调用」和「返回值是不是类型」**，不是「它是不是 `fn`」：

1. 能调用，且返回 `type` → TitleCase（类型函数）。
2. 能调用，且返回非类型 → camelCase（普通函数）。
3. 不能调用 → snake_case（变量、常量、字段、命名空间……）。
4. **函数别名跟随被别名函数的规则**：别名指向普通函数就 camelCase，指向类型函数
   就 TitleCase。别名本身不是 `fn`，但第 3 条对它不适用。

注意「返回类型」指的是函数返回 `type` 这个值本身（典型写法是 `fn ...) type`），
不是指返回值恰好是某个类型的实例。下面这些都算**返回非类型**，用 camelCase：

```zig
pub fn init(instance: *const Instance) !Device
pub fn createDevice() Device
pub fn findDevice() ?Device
pub fn devices() []Device
```

`!Device` 返回的是一个 `Device` **值**（外面包了错误联合），不是 `type`。
`init` 是单个小写单词，camelCase 和 snake_case 在这里写法相同，所以不违规。
只有像 `fn Device(...) type` 这种把类型本身交出去的函数才改用 TitleCase。

```zig
// 命名空间，使用蛇形命名法
const namespace_name = @import("dir_name/file_name.zig");
// 类型声明，使用 TitleCase 命名法
const TypeName = @import("dir_name/TypeName.zig");
// 其他情况，蛇形命名法
var global_var: i32 = undefined;
// 其他情况，蛇形命名法
const const_name = 42;
// 其他情况，蛇形命名法
const primitive_type_alias = f32;
// 其他情况，蛇形命名法
const string_alias = []u8;

// 类型声明，使用 TitleCase 命名法
const StructName = struct {
    field: i32,
};
// 类型声明，使用 TitleCase 命名法
const StructAlias = StructName;

// 可被调用，且返回非类型，使用驼峰命名法
fn functionName(param_name: TypeName) void {
    var functionPointer = functionName;
    functionPointer();
    functionPointer = otherFunction;
    functionPointer();
}

// 可被调用，且返回非类型，使用驼峰命名法
const functionAlias = functionName;

// 可被调用，且返回类型，使用 TitleCase 命名法
fn ListTemplateFunction(
    comptime ChildType: type,
    comptime fixed_size: usize,
) type {
    return List(ChildType, fixed_size);
}

// 可被调用，且返回类型，使用 TitleCase 命名法
fn ShortList(comptime T: type, comptime n: usize) type {
    return struct {
        field_name: [n]T,
        fn methodName() void {}
    };
}

// 其他情况，蛇形命名法
const xml_document =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<document>
    \\</document>
;

// 类型声明，使用 TitleCase 命名法
const XmlParser = struct {
    field: i32,
};

// 可被调用，且返回非类型，使用驼峰命名法
fn readU32Be() u32 {}
```

上面的完整示例来自官方指南（缩进按本项目统一为 4 空格）。官方示例对类型别名
其实不太一致：`StructAlias` 用了 TitleCase，`primitive_type_alias` 和
`string_alias` 却用了 snake_case。**本项目统一为：类型别名一律 TitleCase**，
因为它们在使用处就是类型名；只有 `render_types` 这种模块/命名空间才用
snake_case。

官方示例没有覆盖「0 字段 struct 作为命名空间」的情况，这里补一个：

```zig
// 0 字段 struct 作为命名空间：不能调用 → snake_case
const state = struct {};
```

注意 `ListTemplateFunction` 虽然是 `fn`，但它返回类型，所以是 TitleCase；而
`functionAlias` 虽然不是 `fn`，但可调用且返回非类型，所以是 camelCase。只看
「是不是函数声明」会判错。

补充规则：

- 首字母缩略词、专有名词按普通单词处理，不保留书写时的大写：
  `d3d_device`（不是 `D3DDevice` / `d3dDevice`）、`command_queue_desc`、
  `native_window`。但 `win32` 绑定里的类型名和字段名（`D3D12_COMMAND_QUEUE_DESC`、
  `.Type`）属于外部 API，保持原样。
- 用完整单词，不用自造缩写。`command` 不要写成 `comand` / `cmd`，除非缩写
  已经是领域内公认写法（`vs`、`ps`、`rtv` 这类 D3D 惯用语可以）。
- 不要在名字里编码类型。指针不需要 `_ptr` 后缀（类型里已经写了 `*`），
  可选值不需要 `_opt` 后缀。
- 字段名要能在使用处独立读懂。`queue.desc` 容易有歧义时用
  `queue.command_queue_desc`，但不必把完整类型名机械地抄一遍。

## 项目内部约定（与上游的差异）

- **普通函数（返回非类型）使用 camelCase，类型函数（返回 `type`）使用 TitleCase**。
  这与官方风格指南一致，只是和 Zig 标准库的 snake_case 不同，属于有意选择。
- **常量使用 SCREAMING_SNAKE_CASE**（如 `MAX_PATH_LEN`）。官方指南把常量归入
  「其他情况」并要求 snake_case；本项目沿用既有约定，新常量继续用全大写。
- 类型、字段、变量、文件名、目录名仍按上面的通用规则执行。

## 其他格式

- 4 空格缩进，不使用 Tab。
- 能在同一行打开的大括号就放在同一行。
- 元素超过 2 个的初始化列表，每个元素单独一行，并在最后一个元素后保留逗号。
