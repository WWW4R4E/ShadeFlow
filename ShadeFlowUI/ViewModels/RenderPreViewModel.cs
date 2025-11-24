using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Dispatching;
using ShadeFlow.Natives;
using System;
using System.Threading.Tasks;

namespace ShadeFlow.ViewModels
{
    public partial class RenderPreViewModel : ObservableObject
    {
        private static readonly RenderPreViewModel _instance = new RenderPreViewModel();
        
        private bool _isInitialized = false;
        private bool _isDisposed = false;
        private double _dpiScale = 1.0;
        private DispatcherQueueTimer _renderTimer;
        private bool _isRenderLoopRunning = false;

        #region ObservableProperty
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
        #endregion

        private RenderPreViewModel()
        {
        }
        public static RenderPreViewModel Instance => _instance;

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
                string projectRoot = null;
                string currentDir = AppContext.BaseDirectory;

                while (!string.IsNullOrEmpty(currentDir))
                {
                    if (System.IO.Directory.Exists(System.IO.Path.Combine(currentDir, "ShadeFlowNative")) &&
                        System.IO.Directory.Exists(System.IO.Path.Combine(currentDir, "ShadeFlowUI")))
                    {
                        projectRoot = currentDir;
                        break;
                    }

                    var parent = System.IO.Directory.GetParent(currentDir);
                    if (parent == null) break;
                    currentDir = parent.FullName;
                }

                if (projectRoot == null)
                {
                    projectRoot = AppContext.BaseDirectory;
                }

                string vertexShaderPath = System.IO.Path.Combine(projectRoot, "ShadeFlowNative", "zig-out", "shaders", "TriangleVS.cso");
                string pixelShaderPath = System.IO.Path.Combine(projectRoot, "ShadeFlowNative", "zig-out", "shaders", "TrianglePS.cso");

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

        private void RegisterLogCallback()
        {
            _logCallbackRef = OnNativeLogReceived;
            ShadeFlowNative.RegisterLogCallback(_logCallbackRef);
            System.Diagnostics.Debug.WriteLine("Native log callback registered");
        }

        // 日志回调
        private static ShadeFlowNative.LogCallback _logCallbackRef;
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
    }
}