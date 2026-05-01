using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Diagnostics;

namespace ShadeFlow.Natives
{
    /// <summary>
    /// Zig原生库的C#包装类，提供P/Invoke接口
    /// 这个类用于从C#调用Zig编写的DirectX11渲染库
    /// </summary>
    public static class ShadeFlowNative
    {
        /// <summary>
        /// 日志级别枚举
        /// </summary>
        public enum LogLevel
        {
            Debug,
            Info,
            Warning,
            Error
        }

        /// <summary>
        /// 日志回调委托
        /// </summary>
        /// <param name="level">日志级别</param>
        /// <param name="message">日志消息</param>
        public delegate void LogCallback(LogLevel level, string message);

        /// <summary>
        /// Zig库的DLL名称
        /// </summary>
        private const string DllName = "ShadeFlowNative.dll";

        /// <summary>
        /// 表示一个3D顶点（位置和颜色）
        /// 与Zig端的Vertex结构体对应
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct Vertex
        {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)]
            public float[] position;

            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
            public float[] color;

            /// <summary>
            /// 创建一个新的顶点
            /// </summary>
            /// <param name="x">X坐标</param>
            /// <param name="y">Y坐标</param>
            /// <param name="z">Z坐标</param>
            /// <param name="r">红色分量</param>
            /// <param name="g">绿色分量</param>
            /// <param name="b">蓝色分量</param>
            /// <param name="a">透明度</param>
            public Vertex(float x, float y, float z, float r, float g, float b, float a)
            {
                position = new float[] { x, y, z };
                color = new float[] { r, g, b, a };
            }
        }

        /// <summary>
        /// 使用外部交换链创建渲染引擎
        /// </summary>
        /// <param name="swapChainPtr">外部交换链指针</param>
        /// <param name="width">渲染宽度</param>
        /// <param name="height">渲染高度</param>
        /// <returns>交换链指针</returns>
        /// <summary>
        /// 创建引擎实例，使用Composition模式（用于WinUI 3）
        /// </summary>
        /// <param name="width">渲染宽度</param>
        /// <param name="height">渲染高度</param>
        /// <returns>是否成功创建引擎</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern bool ShadeFlow_CreateEngineForComposition(uint width, uint height);

        /// <summary>
        /// 获取交换链指针，用于WinUI 3 Composition绑定
        /// </summary>
        /// <returns>交换链指针</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr ShadeFlow_GetSwapChain();

        /// <summary>
        /// 调整渲染器大小
        /// </summary>
        /// <param name="width">新宽度</param>
        /// <param name="height">新高度</param>
        /// <returns>是否成功调整大小</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern bool ShadeFlow_ResizeRenderer(uint width, uint height);

        /// <summary>
        /// 渲染一帧
        /// </summary>
        /// <returns>是否成功渲染</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern bool ShadeFlow_RenderFrame();

        /// <summary>
        /// 添加一个三角形到渲染场景
        /// </summary>
        /// <param name="vertices">三个顶点组成的数组</param>
        /// <returns>成功返回true，失败返回false</returns>
        /// <summary>
        /// 添加渲染对象（简单三角形）
        /// </summary>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddTriangleObject(string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 添加带索引的渲染对象（四边形）
        /// </summary>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddQuadObject(string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 添加旋转立方体渲染对象
        /// </summary>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddRotatingCubeObject(string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 清除所有渲染对象
        /// </summary>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern bool ShadeFlow_ClearRenderObjects();

        /// <summary>
        /// 检查引擎是否已初始化
        /// </summary>
        /// <returns>已初始化返回true，否则返回false</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern bool ShadeFlow_IsEngineInitialized();
        

        /// <summary>
        /// 清理资源
        /// </summary>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ShadeFlow_Cleanup();

        /// <summary>
        /// 注册日志回调函数
        /// </summary>
        /// <param name="callback">日志回调函数指针</param>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ShadeFlow_RegisterLogCallback(IntPtr callback);

        // 日志回调的内部委托定义，用于转换
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void NativeLogCallback(int level, IntPtr message);

        // 存储当前注册的日志回调，防止被GC回收
        private static LogCallback _currentLogCallback;
        private static NativeLogCallback _nativeLogCallback;

        /// <summary>
        /// 注册日志回调，提供更好的错误处理
        /// </summary>
        /// <param name="callback">日志回调函数</param>
        public static void RegisterLogCallback(LogCallback callback)
        {
            try
            {
                _currentLogCallback = callback; // 保持引用以防止被GC回收
                
                // 创建内部的原生回调
                _nativeLogCallback = (level, messagePtr) => {
                    if (callback != null && messagePtr != IntPtr.Zero)
                    {
                        string message = Marshal.PtrToStringAnsi(messagePtr);
                        if (message != null)
                        {
                            callback((LogLevel)level, message);
                        }
                    }
                };
                
                // 获取原生回调的指针并传递给Zig
                IntPtr callbackPtr = Marshal.GetFunctionPointerForDelegate(_nativeLogCallback);
                ShadeFlow_RegisterLogCallback(callbackPtr);
                
                Debug.WriteLine("日志回调注册成功");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"注册日志回调失败: {ex.Message}");
                throw;
            }
        }

        // 便捷方法提供更友好的C#接口

        /// <summary>
        /// 使用外部交换链创建渲染引擎的包装方法
        /// </summary>
        /// <param name="swapChainPtr">外部交换链指针</param>
        /// <param name="width">渲染宽度</param>
        /// <param name="height">渲染高度</param>
        /// <returns>交换链指针</returns>
        /// <summary>
        /// 创建引擎实例的包装方法
        /// </summary>
        /// <param name="width">渲染宽度</param>
        /// <param name="height">渲染高度</param>
        /// <returns>是否成功创建引擎</returns>
        public static bool CreateEngineForComposition(uint width, uint height)
        {
            try
            {
                Debug.WriteLine($"正在创建 ShadeFlow 引擎，尺寸 {width}x{height}");
                Debug.WriteLine($"正在查找库文件: {Path.GetFullPath(DllName)}");
                
                bool result = ShadeFlow_CreateEngineForComposition(width, height);
                
                if (result)
                {
                    Debug.WriteLine("引擎创建成功");
                    return true;
                }
                else
                {
                    Debug.WriteLine("创建引擎失败");
                    // 检查是否为DLL加载问题
                    if (!File.Exists(DllName))
                    {
                        throw new Exception($"Failed to load ShadeFlow library. File not found: {DllName}");
                    }
                    throw new Exception("Failed to create ShadeFlow engine. Check Zig output logs for details.");
                }
            }
            catch (DllNotFoundException dllEx)
            {
                Debug.WriteLine($"DLL 未找到: {DllName}。错误: {dllEx.Message}");
                throw new Exception($"Failed to load ShadeFlow library: {dllEx.Message}", dllEx);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"创建引擎错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 获取交换链的包装方法
        /// </summary>
        /// <returns>交换链指针</returns>
        public static IntPtr GetSwapChain()
        {
            try
            {
                IntPtr result = ShadeFlow_GetSwapChain();
                
                if (result != IntPtr.Zero)
                {
                    Debug.WriteLine("成功获取交换链指针");
                    return result;
                }
                else
                {
                    Debug.WriteLine("获取交换链指针失败");
                    return IntPtr.Zero;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"获取交换链错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 调整渲染器大小的包装方法
        /// </summary>
        /// <param name="width">新宽度</param>
        /// <param name="height">新高度</param>
        /// <returns>是否成功调整大小</returns>
        public static bool ResizeRenderer(uint width, uint height)
        {
            try
            {
                bool result = ShadeFlow_ResizeRenderer(width, height);
                
                if (result)
                {
                    Debug.WriteLine($"渲染器已调整大小为 {width}x{height}");
                    return true;
                }
                else
                {
                    Debug.WriteLine($"调整渲染器大小失败: {width}x{height}");
                    return false;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"调整渲染器大小错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 渲染一帧的包装方法
        /// </summary>
        /// <returns>是否成功渲染</returns>
        public static bool RenderFrame()
        {
            try
            {
                bool result = ShadeFlow_RenderFrame();
                
                if (!result)
                {
                    Debug.WriteLine("渲染帧失败");
                }
                
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"渲染帧错误: {ex.Message}");
                throw;
            }
        }


        /// <summary>
        /// 添加带参数的立方体
        /// </summary>
        /// <param name="size">立方体大小</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddCubeWithParams(float size, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 添加带参数的球体
        /// </summary>
        /// <param name="radius">球体半径</param>
        /// <param name="segments">分段数</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddSphereWithParams(float radius, uint segments, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 添加带参数的圆柱体
        /// </summary>
        /// <param name="radius">圆柱体半径</param>
        /// <param name="height">圆柱体高度</param>
        /// <param name="segments">分段数</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddCylinderWithParams(float radius, float height, uint segments, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 添加带参数的圆锥体
        /// </summary>
        /// <param name="radius">圆锥体底面半径</param>
        /// <param name="height">圆锥体高度</param>
        /// <param name="segments">分段数</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddConeWithParams(float radius, float height, uint segments, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path);


        /// <summary>
        /// 添加带参数的立方体的包装方法
        /// </summary>
        /// <param name="size">立方体大小</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddCubeWithParams(float size, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path)
        {
            try
            {
                if (!ShadeFlow_AddCubeWithParams(size, pos_x, pos_y, pos_z, vertex_shader_path, pixel_shader_path))
                {
                    throw new Exception("Failed to add cube with params to renderer");
                }
                Debug.WriteLine($"立方体已成功添加，大小 {size}，位置 ({pos_x}, {pos_y}, {pos_z})，着色器: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"添加立方体参数错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 添加带参数的立方体的包装方法（默认位置）
        /// </summary>
        /// <param name="size">立方体大小</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddCubeWithParams(float size, string vertex_shader_path, string pixel_shader_path)
        {
            AddCubeWithParams(size, 0.0f, 0.0f, 0.0f, vertex_shader_path, pixel_shader_path);
        }

        /// <summary>
        /// 添加带参数的球体的包装方法
        /// </summary>
        /// <param name="radius">球体半径</param>
        /// <param name="segments">分段数</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddSphereWithParams(float radius, uint segments, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path)
        {
            try
            {
                if (!ShadeFlow_AddSphereWithParams(radius, segments, pos_x, pos_y, pos_z, vertex_shader_path, pixel_shader_path))
                {
                    throw new Exception("Failed to add sphere with params to renderer");
                }
                Debug.WriteLine($"球体已成功添加，半径 {radius}，分段 {segments}，位置 ({pos_x}, {pos_y}, {pos_z})，着色器: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"添加球体参数错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 添加带参数的球体的包装方法（默认位置）
        /// </summary>
        /// <param name="radius">球体半径</param>
        /// <param name="segments">分段数</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddSphereWithParams(float radius, uint segments, string vertex_shader_path, string pixel_shader_path)
        {
            AddSphereWithParams(radius, segments, 0.0f, 0.0f, 0.0f, vertex_shader_path, pixel_shader_path);
        }

        /// <summary>
        /// 添加带参数的圆柱体的包装方法
        /// </summary>
        /// <param name="radius">圆柱体半径</param>
        /// <param name="height">圆柱体高度</param>
        /// <param name="segments">分段数</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddCylinderWithParams(float radius, float height, uint segments, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path)
        {
            try
            {
                if (!ShadeFlow_AddCylinderWithParams(radius, height, segments, pos_x, pos_y, pos_z, vertex_shader_path, pixel_shader_path))
                {
                    throw new Exception("Failed to add cylinder with params to renderer");
                }
                Debug.WriteLine($"圆柱体已成功添加，半径 {radius}，高度 {height}，分段 {segments}，位置 ({pos_x}, {pos_y}, {pos_z})，着色器: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"添加圆柱体参数错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 添加带参数的圆柱体的包装方法（默认位置）
        /// </summary>
        /// <param name="radius">圆柱体半径</param>
        /// <param name="height">圆柱体高度</param>
        /// <param name="segments">分段数</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddCylinderWithParams(float radius, float height, uint segments, string vertex_shader_path, string pixel_shader_path)
        {
            AddCylinderWithParams(radius, height, segments, 0.0f, 0.0f, 0.0f, vertex_shader_path, pixel_shader_path);
        }

        /// <summary>
        /// 添加带参数的圆锥体的包装方法
        /// </summary>
        /// <param name="radius">圆锥体底面半径</param>
        /// <param name="height">圆锥体高度</param>
        /// <param name="segments">分段数</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddConeWithParams(float radius, float height, uint segments, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path)
        {
            try
            {
                if (!ShadeFlow_AddConeWithParams(radius, height, segments, pos_x, pos_y, pos_z, vertex_shader_path, pixel_shader_path))
                {
                    throw new Exception("Failed to add cone with params to renderer");
                }
                Debug.WriteLine($"圆锥体已成功添加，半径 {radius}，高度 {height}，分段 {segments}，位置 ({pos_x}, {pos_y}, {pos_z})，着色器: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"添加圆锥体参数错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 添加带参数的圆锥体的包装方法（默认位置）
        /// </summary>
        /// <param name="radius">圆锥体底面半径</param>
        /// <param name="height">圆锥体高度</param>
        /// <param name="segments">分段数</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddConeWithParams(float radius, float height, uint segments, string vertex_shader_path, string pixel_shader_path)
        {
            AddConeWithParams(radius, height, segments, 0.0f, 0.0f, 0.0f, vertex_shader_path, pixel_shader_path);
        }

        /// <summary>
        /// 几何形状类型枚举
        /// </summary>
        public enum GeometryType
        {
            Triangle = 0,
            Quad = 1,
            Cube = 2,
            Sphere = 3,
            Cylinder = 4,
            Cone = 5
        }

        /// <summary>
        /// 添加几何对象（使用默认参数）
        /// </summary>
        /// <param name="geometry_type">几何形状类型</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddGeometryObject(int geometry_type, string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 添加带参数的几何对象
        /// </summary>
        /// <param name="geometry_type">几何形状类型</param>
        /// <param name="params">几何形状参数</param>
        /// <param name="pos_x">X坐标</param>
        /// <param name="pos_y">Y坐标</param>
        /// <param name="pos_z">Z坐标</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        /// <returns>是否成功添加</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern bool ShadeFlow_AddGeometryObjectWithParams(int geometry_type, IntPtr @params, float pos_x, float pos_y, float pos_z, string vertex_shader_path, string pixel_shader_path);

        /// <summary>
        /// 释放引擎资源的包装方法
        /// </summary>
        // ReleaseEngine方法已被Cleanup替代，不再需要单独的释放方法

        /// <summary>
        /// 检查引擎是否已初始化
        /// </summary>
        /// <returns>引擎是否已初始化</returns>
        public static bool IsEngineInitialized()
        {    
            try
            {
                bool result = ShadeFlow_IsEngineInitialized();
                Debug.WriteLine($"引擎初始化状态: {result}");
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"检查引擎初始化错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 清除所有渲染对象的包装方法
        /// </summary>
        public static bool ClearRenderObjects()
        {    
            try
            {
                bool result = ShadeFlow_ClearRenderObjects();
                if (result)
                {
                    Debug.WriteLine("所有渲染对象已成功清除");
                }
                else
                {
                    Debug.WriteLine("清除渲染对象失败");
                }
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"清除渲染对象错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 清理资源的包装方法
        /// </summary>
        public static void Cleanup()
        {
            try
            {
                ShadeFlow_Cleanup();
                Debug.WriteLine("资源清理成功");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"清理过程错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 添加几何对象的包装方法（使用默认参数）
        /// </summary>
        /// <param name="geometry_type">几何形状类型</param>
        /// <param name="vertex_shader_path">顶点着色器路径</param>
        /// <param name="pixel_shader_path">像素着色器路径</param>
        public static void AddGeometryObject(GeometryType geometry_type, string vertex_shader_path, string pixel_shader_path)
        {
            try
            {
                if (!ShadeFlow_AddGeometryObject((int)geometry_type, vertex_shader_path, pixel_shader_path))
                {
                    throw new Exception("Failed to add geometry object");
                }
                Debug.WriteLine($"几何对象已成功添加，类型 {geometry_type}，着色器: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"添加几何对象错误: {ex.Message}");
                throw;
            }
        }

        // 相机控制相关的DllImport声明

        /// <summary>
        /// 获取相机位置
        /// </summary>
        /// <param name="x">X坐标输出</param>
        /// <param name="y">Y坐标输出</param>
        /// <param name="z">Z坐标输出</param>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ShadeFlow_GetCameraPosition(out float x, out float y, out float z);

        /// <summary>
        /// 设置相机位置
        /// </summary>
        /// <param name="x">X坐标</param>
        /// <param name="y">Y坐标</param>
        /// <param name="z">Z坐标</param>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ShadeFlow_SetCameraPosition(float x, float y, float z);

        /// <summary>
        /// 获取相机距离
        /// </summary>
        /// <returns>相机距离</returns>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern float ShadeFlow_GetCameraDistance();

        /// <summary>
        /// 设置相机距离
        /// </summary>
        /// <param name="distance">相机距离</param>
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ShadeFlow_SetCameraDistance(float distance);

        // 相机控制相关的包装方法

        /// <summary>
        /// 获取相机位置的包装方法
        /// </summary>
        /// <returns>相机位置</returns>
        public static (float, float, float) GetCameraPosition()
        {
            try
            {
                float x, y, z;
                ShadeFlow_GetCameraPosition(out x, out y, out z);
                return (x, y, z);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"获取相机位置错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 设置相机位置的包装方法
        /// </summary>
        /// <param name="x">X坐标</param>
        /// <param name="y">Y坐标</param>
        /// <param name="z">Z坐标</param>
        public static void SetCameraPosition(float x, float y, float z)
        {
            try
            {
                ShadeFlow_SetCameraPosition(x, y, z);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"设置相机位置错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 获取相机距离的包装方法
        /// </summary>
        /// <returns>相机距离</returns>
        public static float GetCameraDistance()
        {
            try
            {
                return ShadeFlow_GetCameraDistance();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"获取相机距离错误: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// 设置相机距离的包装方法
        /// </summary>
        /// <param name="distance">相机距离</param>
        public static void SetCameraDistance(float distance)
        {
            try
            {
                ShadeFlow_SetCameraDistance(distance);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"设置相机距离错误: {ex.Message}");
                throw;
            }
        }
    }
}