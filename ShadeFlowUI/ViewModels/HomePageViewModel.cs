using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Dispatching;
using ShadeFlow.Models;
using ShadeFlow.Natives;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace ShadeFlow.ViewModels
{
    public partial class HomePageViewModel : ObservableObject
    {
        private bool _isInitialized = false;
        private bool _isDisposed = false;
        private double _dpiScale = 1.0;
        private bool _isRenderLoopRunning = false;
        private DispatcherQueueTimer _renderTimer;

        // 渲染状态
        [ObservableProperty]
        private bool _isRendering = false;

        // 渲染错误信息
        [ObservableProperty]
        private string _errorMessage = string.Empty;

        // 渲染器尺寸
        [ObservableProperty]
        private int _renderWidth = 800;

        [ObservableProperty]
        private int _renderHeight = 600;

        // 节点集合 - 用于NodeEditor的数据绑定
        [ObservableProperty]
        private ObservableCollection<NodeBase> _nodes = new ObservableCollection<NodeBase>();

        // 渲染器操作命令属性
        [RelayCommand]
        private async Task InitializeRendererAsync()
        {
            if (_isInitialized) return;

            try
            {
                System.Diagnostics.Debug.WriteLine($"Initializing renderer with size: {RenderWidth}x{RenderHeight}");

                // 调用Zig库创建引擎
                if (!ShadeFlowNative.ShadeFlow_CreateEngineForComposition((uint)RenderWidth, (uint)RenderHeight))
                {
                    throw new Exception("Failed to create DirectX engine");
                }

                // 添加默认渲染对象
                string vertexShaderPath = "G:\\ShadeFlow\\ShadeFlowNative\\zig-out\\shaders\\TriangleVS.cso";
                string pixelShaderPath = "G:\\ShadeFlow\\ShadeFlowNative\\zig-out\\shaders\\TrianglePS.cso";

                if (!ShadeFlowNative.ShadeFlow_AddTriangleObject(vertexShaderPath, pixelShaderPath))
                {
                    System.Diagnostics.Debug.WriteLine("Failed to add triangle object");
                }

                if (!ShadeFlowNative.ShadeFlow_AddQuadObject(vertexShaderPath, pixelShaderPath))
                {
                    System.Diagnostics.Debug.WriteLine("Failed to add quad object");
                }

                _isInitialized = true;
                IsRendering = true;
                StartRenderLoop();

                System.Diagnostics.Debug.WriteLine("Renderer initialized successfully");
            }
            catch (Exception ex)
            {
                ErrorMessage = $"Failed to initialize renderer: {ex.Message}";
                System.Diagnostics.Debug.WriteLine($"Error initializing renderer: {ex.Message}");
                throw;
            }
        }

        [RelayCommand]
        private void ResizeRenderer()
        {
            if (!_isInitialized || _isDisposed || RenderWidth <= 0 || RenderHeight <= 0)
                return;

            try
            {
                ShadeFlowNative.ShadeFlow_ResizeRenderer((uint)RenderWidth, (uint)RenderHeight);
                System.Diagnostics.Debug.WriteLine($"Renderer resized to {RenderWidth}x{RenderHeight}");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Error resizing renderer: {ex.Message}");
            }
        }

        public IntPtr GetSwapChain()
        {
            return _isInitialized ? ShadeFlowNative.ShadeFlow_GetSwapChain() : IntPtr.Zero;
        }

        [RelayCommand]
        private void Cleanup()
        {
            if (_isDisposed) return;

            _isDisposed = true;

            try
            {
                StopRenderLoop();
                ShadeFlowNative.ShadeFlow_Cleanup();
                _isInitialized = false;
                System.Diagnostics.Debug.WriteLine("Renderer cleaned up");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Error during cleanup: {ex.Message}");
            }
        }

        // 日志回调
        private static ShadeFlowNative.LogCallback _logCallbackRef;

        public HomePageViewModel()
        {
            RegisterLogCallback();
            GenerateTestNodes(); // 生成测试数据
        }

        private async Task InitializeRendererAsyncImpl(int width, int height, double dpiScale)
        {
            if (_isInitialized) return;

            try
            {
                RenderWidth = width;
                RenderHeight = height;
                _dpiScale = dpiScale;

                System.Diagnostics.Debug.WriteLine($"Initializing renderer with size: {width}x{height}");

                // 调用Zig库创建引擎
                if (!ShadeFlowNative.ShadeFlow_CreateEngineForComposition((uint)width, (uint)height))
                {
                    throw new Exception("Failed to create DirectX engine");
                }

                // 添加默认渲染对象
                string vertexShaderPath = "D:\\ShadeFlow\\ShadeFlowNative\\zig-out\\shaders\\TriangleVS.cso";
                string pixelShaderPath = "D:\\ShadeFlow\\ShadeFlowNative\\zig-out\\shaders\\TrianglePS.cso";

                if (!ShadeFlowNative.ShadeFlow_AddTriangleObject(vertexShaderPath, pixelShaderPath))
                {
                    System.Diagnostics.Debug.WriteLine("Failed to add triangle object");
                }

                if (!ShadeFlowNative.ShadeFlow_AddQuadObject(vertexShaderPath, pixelShaderPath))
                {
                    System.Diagnostics.Debug.WriteLine("Failed to add quad object");
                }

                _isInitialized = true;
                IsRendering = true;
                StartRenderLoop();

                System.Diagnostics.Debug.WriteLine("Renderer initialized successfully");
            }
            catch (Exception ex)
            {
                ErrorMessage = $"Failed to initialize renderer: {ex.Message}";
                System.Diagnostics.Debug.WriteLine($"Error initializing renderer: {ex.Message}");
                throw;
            }
        }

        private void ResizeRendererImpl(int width, int height)
        {
            if (!_isInitialized || _isDisposed || width <= 0 || height <= 0)
                return;

            try
            {
                RenderWidth = width;
                RenderHeight = height;
                ShadeFlowNative.ShadeFlow_ResizeRenderer((uint)width, (uint)height);
                System.Diagnostics.Debug.WriteLine($"Renderer resized to {width}x{height}");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Error resizing renderer: {ex.Message}");
            }
        }

        private IntPtr GetSwapChainImpl()
        {
            return _isInitialized ? ShadeFlowNative.ShadeFlow_GetSwapChain() : IntPtr.Zero;
        }

        private void StartRenderLoop()
        {
            if (_isRenderLoopRunning) return;

            _isRenderLoopRunning = true;

            var dispatcherQueue = DispatcherQueue.GetForCurrentThread();
            if (dispatcherQueue == null)
            {
                System.Diagnostics.Debug.WriteLine("Failed to get DispatcherQueue for render loop");
                return;
            }

            _renderTimer = dispatcherQueue.CreateTimer();
            _renderTimer.Interval = TimeSpan.FromSeconds(1.0 / 60.0); // 60 FPS
            _renderTimer.IsRepeating = true;
            _renderTimer.Tick += (s, e) => RenderFrame();
            _renderTimer.Start();

            System.Diagnostics.Debug.WriteLine("Render loop started");
        }

        private void StopRenderLoop()
        {
            if (!_isRenderLoopRunning) return;

            _isRenderLoopRunning = false;
            IsRendering = false;

            if (_renderTimer != null)
            {
                _renderTimer.Stop();
                _renderTimer = null;
            }

            System.Diagnostics.Debug.WriteLine("Render loop stopped");
        }

        private void RenderFrame()
        {
            if (!_isInitialized || _isDisposed) return;

            try
            {
                ShadeFlowNative.ShadeFlow_RenderFrame();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Error rendering frame: {ex.Message}");
            }
        }

        private void CleanupImpl()
        {
            if (_isDisposed) return;

            _isDisposed = true;

            try
            {
                StopRenderLoop();
                ShadeFlowNative.ShadeFlow_Cleanup();
                _isInitialized = false;
                System.Diagnostics.Debug.WriteLine("Renderer cleaned up");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Error during cleanup: {ex.Message}");
            }
        }

        private void RegisterLogCallback()
        {
            _logCallbackRef = OnNativeLogReceived;
            ShadeFlowNative.RegisterLogCallback(_logCallbackRef);
            System.Diagnostics.Debug.WriteLine("Native log callback registered");
        }

        private static void OnNativeLogReceived(ShadeFlowNative.LogLevel level, string message)
        {
            string levelPrefix = level switch
            {
                ShadeFlowNative.LogLevel.Debug => "[DEBUG]",
                ShadeFlowNative.LogLevel.Info => "[INFO]",
                ShadeFlowNative.LogLevel.Warning => "[WARNING]",
                ShadeFlowNative.LogLevel.Error => "[ERROR]",
                _ => "[UNKNOWN]"
            };

            System.Diagnostics.Debug.WriteLine($"{levelPrefix} {message}");
        }

        /// <summary>
        /// 生成测试节点数据
        /// </summary>
        private void GenerateTestNodes()
        {
            Nodes.Clear();

            // 创建多个测试节点
            for (int i = 0; i < 5; i++)
            {
                var node = new ShaderNode()
                {
                    Title = $"Shader Node {i + 1}",
                    Description = $"This is shader node {i + 1}",
                    X = 100 + i * 250,
                    Y = 100 + (i % 2) * 150,
                    ShaderType = i % 2 == 0 ? "Vertex" : "Fragment"
                };

                Nodes.Add(node);
            }

            // 再添加一些普通节点
            for (int i = 0; i < 3; i++)
            {
                var node = new NodeBase()
                {
                    Title = $"Generic Node {i + 1}",
                    Description = $"This is a generic node {i + 1}",
                    X = 150 + i * 300,
                    Y = 400
                };

                Nodes.Add(node);
            }

            System.Diagnostics.Debug.WriteLine($"Generated {Nodes.Count} test nodes");
        }
    }
}