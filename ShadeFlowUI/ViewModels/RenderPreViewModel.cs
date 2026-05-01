using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Dispatching;
using ShadeFlow.Natives;
using System;
using System.Diagnostics;
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
                Debug.WriteLine($"正在初始化渲染器，尺寸: {RenderWidth}x{RenderHeight}");

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
                _isInitialized = true;
                IsRendering = true;
                StartRenderLoop();

                Debug.WriteLine("渲染器初始化成功");
            }
            catch (Exception ex)
            {
                ErrorMessage = $"Failed to initialize renderer: {ex.Message}";
                Debug.WriteLine($"初始化渲染器错误: {ex.Message}");
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
                Debug.WriteLine($"渲染器已调整大小为 {RenderWidth}x{RenderHeight}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"调整渲染器大小错误: {ex.Message}");
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
                Debug.WriteLine("渲染器已清理");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"清理过程错误: {ex.Message}");
            }
        }

        private void StartRenderLoop()
        {
            if (_isRenderLoopRunning) return;

            _isRenderLoopRunning = true;

            var dispatcherQueue = DispatcherQueue.GetForCurrentThread();
            if (dispatcherQueue == null)
            {
                Debug.WriteLine("获取渲染循环的 DispatcherQueue 失败");
                return;
            }

            _renderTimer = dispatcherQueue.CreateTimer();
            _renderTimer.Interval = TimeSpan.FromSeconds(1.0 / 60.0); // 60 FPS
            _renderTimer.IsRepeating = true;
            _renderTimer.Tick += (s, e) => RenderFrame();
            _renderTimer.Start();

            Debug.WriteLine("渲染循环已启动");
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

            Debug.WriteLine("渲染循环已停止");
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
                Debug.WriteLine($"渲染帧错误: {ex.Message}");
            }
        }

        private void RegisterLogCallback()
        {
            _logCallbackRef = OnNativeLogReceived;
            ShadeFlowNative.RegisterLogCallback(_logCallbackRef);
            Debug.WriteLine("原生日志回调已注册");
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

            Debug.WriteLine($"{levelPrefix} {message}");
        }
    }
}