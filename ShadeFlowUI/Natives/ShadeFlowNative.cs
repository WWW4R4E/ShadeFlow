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
                
                Debug.WriteLine("Log callback registered successfully");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to register log callback: {ex.Message}");
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
                Debug.WriteLine($"Creating ShadeFlow engine with size {width}x{height}");
                Debug.WriteLine($"Looking for library at: {Path.GetFullPath(DllName)}");
                
                bool result = ShadeFlow_CreateEngineForComposition(width, height);
                
                if (result)
                {
                    Debug.WriteLine("Engine created successfully");
                    return true;
                }
                else
                {
                    Debug.WriteLine("Failed to create engine");
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
                Debug.WriteLine($"DLL not found: {DllName}. Error: {dllEx.Message}");
                throw new Exception($"Failed to load ShadeFlow library: {dllEx.Message}", dllEx);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error creating engine: {ex.Message}");
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
                    Debug.WriteLine("Successfully obtained swap chain pointer");
                    return result;
                }
                else
                {
                    Debug.WriteLine("Failed to obtain swap chain pointer");
                    return IntPtr.Zero;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error getting swap chain: {ex.Message}");
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
                    Debug.WriteLine($"Renderer resized to {width}x{height}");
                    return true;
                }
                else
                {
                    Debug.WriteLine($"Failed to resize renderer to {width}x{height}");
                    return false;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error resizing renderer: {ex.Message}");
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
                    Debug.WriteLine("Failed to render frame");
                }
                
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error rendering frame: {ex.Message}");
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
                Debug.WriteLine($"Cube with size {size} at position ({pos_x}, {pos_y}, {pos_z}) added successfully with shaders: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error adding cube with params: {ex.Message}");
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
                Debug.WriteLine($"Sphere with radius {radius}, segments {segments} at position ({pos_x}, {pos_y}, {pos_z}) added successfully with shaders: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error adding sphere with params: {ex.Message}");
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
                Debug.WriteLine($"Cylinder with radius {radius}, height {height}, segments {segments} at position ({pos_x}, {pos_y}, {pos_z}) added successfully with shaders: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error adding cylinder with params: {ex.Message}");
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
                Debug.WriteLine($"Cone with radius {radius}, height {height}, segments {segments} at position ({pos_x}, {pos_y}, {pos_z}) added successfully with shaders: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error adding cone with params: {ex.Message}");
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
                Debug.WriteLine($"Engine initialization status: {result}");
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error checking engine initialization: {ex.Message}");
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
                    Debug.WriteLine("All render objects cleared successfully");
                }
                else
                {
                    Debug.WriteLine("Failed to clear render objects");
                }
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error clearing render objects: {ex.Message}");
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
                Debug.WriteLine("Resources cleaned up successfully");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error during cleanup: {ex.Message}");
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
                Debug.WriteLine($"Geometry object of type {geometry_type} added successfully with shaders: {vertex_shader_path}, {pixel_shader_path}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error adding geometry object: {ex.Message}");
                throw;
            }
        }
    }
}