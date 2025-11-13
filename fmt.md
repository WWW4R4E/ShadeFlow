## 文件与目录命名

| 元素                                   | 风格                     | 示例                             |
| ------------------------------------ | ---------------------- | ------------------------------ |
| **函数**                               | camelCase              | `initHeap`, `parseArgs`        |
| **变量**                               | snake\_case            | `buffer_len`, `file_name`      |
| **常量**                               | SCREAMING\_SNAKE\_CASE | `MAX_PATH_LEN`, `BUFFER_SIZE`  |
| **类型（struct / enum / union / 类型函数）** | PascalCase             | `StringHashMap`, `List(i32)`   |
| **返回类型的函数**                          | PascalCase             | `List`, `StringHashMap`        |

## 代码内命名

| 元素                                   | 风格                     | 示例                             |
| ------------------------------------ | ---------------------- | ------------------------------ |
| **函数**                               | camelCase              | `initHeap`, `parseArgs`        |
| **变量**                               | snake\_case            | `buffer_len`, `file_name`      |
| **常量**                               | SCREAMING\_SNAKE\_CASE | `MAX_PATH_LEN`, `BUFFER_SIZE`  |
| **类型（struct / enum / union / 类型函数）** | PascalCase             | `StringHashMap`, `List(i32)`   |
| **返回类型的函数**                          | PascalCase             | `List`, `StringHashMap`        |



## 项目结构

```
dx11_zig/
├── src/
│   ├── main.zig                 # 程序入口
│   ├── engine/
│   │   ├── core/
│   │   │   ├── Application.zig  # 应用程序主类
│   │   │   ├── Window.zig       # 窗口管理
│   │   │   ├── Input.zig        # 输入处理
│   │   │   └── Time.zig         # 时间管理
│   │   ├── renderer/
│   │   │   ├── d3d11/
│   │   │   │   ├── Device.zig   # DirectX设备管理
│   │   │   │   ├── SwapChain.zig # 交换链管理
│   │   │   │   ├── Shader.zig   # 着色器管理
│   │   │   │   ├── Buffer.zig   # 缓冲区管理
│   │   │   │   └── Texture.zig  # 纹理管理
│   │   │   ├── Renderer.zig     # 渲染器基类
│   │   │   ├── 2d/
│   │   │   │   ├── SpriteRenderer.zig  # 2D精灵渲染器
│   │   │   │   └── CanvasRenderer.zig  # 2D画布渲染器
│   │   │   └── 3d/
│   │   │       ├── MeshRenderer.zig    # 3D网格渲染器
│   │   │       └── Camera.zig          # 相机管理
│   │   ├── resources/
│   │   │   ├── ResourceManager.zig     # 资源管理器
│   │   │   ├── ModelLoader.zig         # 模型加载器
│   │   │   └── TextureLoader.zig       # 纹理加载器
│   │   └── scripting/
│   │       ├── ScriptEngine.zig        # 脚本引擎接口
│   │       └── csharp/
│   │           └── CSharpInterop.zig   # C#交互层
│   ├── editor/
│   │   ├── NodeEditor.zig      # 节点编辑器主类
│   │   ├── nodes/
│   │   │   ├── Node.zig        # 节点基类
│   │   │   ├── 2d/
│   │   │   │   ├── SpriteNode.zig      # 精灵节点
│   │   │   │   └── CanvasNode.zig      # 画布节点
│   │   │   ├── 3d/
│   │   │   │   ├── MeshNode.zig        # 网格节点
│   │   │   │   └── CameraNode.zig      # 相机节点
│   │   │   └── rendering/
│   │   │       ├── ShaderNode.zig      # 着色器节点
│   │   │       └── MaterialNode.zig    # 材质节点
│   │   ├── ui/
│   │   │   ├── Panel.zig       # 面板基类
│   │   │   ├── NodeGraph.zig   # 节点图控件
│   │   │   └── PropertyEditor.zig      # 属性编辑器
│   │   └── serialization/
│   │       ├── ProjectLoader.zig       # 项目加载器
│   │       └── NodeSerializer.zig      # 节点序列化
│   └── utils/
│       ├── math/
│       │   ├── Vector.zig      # 向量运算
│       │   ├── Matrix.zig      # 矩阵运算
│       │   └── Quaternion.zig  # 四元数运算
│       ├── Logger.zig          # 日志系统
│       └── Memory.zig          # 内存管理
├── assets/                     # 资源文件夹
│   ├── shaders/                # 着色器文件
│   ├── models/                 # 模型文件
│   └── textures/               # 纹理文件
├── lib/                        # 第三方库
├── build.zig                   # 构建脚本
└── build.zig.zon               # 依赖配置
```