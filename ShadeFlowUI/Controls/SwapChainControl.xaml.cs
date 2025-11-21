using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using ShadeFlow.Natives;
using ShadeFlow.ViewModels;
using System;
using System.Threading.Tasks;
using System.Windows.Input;
using WinRT;

namespace ShadeFlow.Controls
{
	public sealed partial class SwapChainControl : SwapChainPanel
	{
		private ISwapChainPanelNative _swapChainPanelNative;
		private IntPtr _swapChain = IntPtr.Zero;
		private bool _isInitialized = false;
		private bool _isDisposed = false;

		public SwapChainControl()
		{
			InitializeComponent();
		}

		// 添加支持x:Bind的命令属性
		public ICommand InitializeRendererCommand
		{
			get { return (ICommand)GetValue(InitializeRendererCommandProperty); }
			set { SetValue(InitializeRendererCommandProperty, value); }
		}

		public static readonly DependencyProperty InitializeRendererCommandProperty =
			DependencyProperty.Register(nameof(InitializeRendererCommand), typeof(ICommand), typeof(SwapChainControl),
				new PropertyMetadata(null));

		public ICommand ResizeRendererCommand
		{
			get { return (ICommand)GetValue(ResizeRendererCommandProperty); }
			set { SetValue(ResizeRendererCommandProperty, value); }
		}

		public static readonly DependencyProperty ResizeRendererCommandProperty =
			DependencyProperty.Register(nameof(ResizeRendererCommand), typeof(ICommand), typeof(SwapChainControl),
				new PropertyMetadata(null));



		public ICommand CleanupRendererCommand
		{
			get { return (ICommand)GetValue(CleanupRendererCommandProperty); }
			set { SetValue(CleanupRendererCommandProperty, value); }
		}

		public static readonly DependencyProperty CleanupRendererCommandProperty =
			DependencyProperty.Register(nameof(CleanupRendererCommand), typeof(ICommand), typeof(SwapChainControl),
				new PropertyMetadata(null));

		private async void OnLoaded(object sender, RoutedEventArgs e)
		{
			await InitializeSwapChainAsync();
		}

		private void OnUnloaded(object sender, RoutedEventArgs e)
		{
			Cleanup();
		}

		private void OnSizeChanged(object sender, SizeChangedEventArgs e)
		{
			if (_isInitialized && !_isDisposed)
			{
				UpdateSwapChainSize();
			}
		}

		private async Task InitializeSwapChainAsync()
		{
			if (_isInitialized || InitializeRendererCommand == null) return;

			try
			{
				// 确保控件有有效尺寸
				if (ActualWidth <= 0 || ActualHeight <= 0)
				{
					await Task.Delay(100);
					if (ActualWidth <= 0 || ActualHeight <= 0)
					{
						SizeChanged += OnFirstTimeSizeChanged;
						return;
					}
				}

				_swapChainPanelNative = this.As<ISwapChainPanelNative>();
				if (_swapChainPanelNative == null)
				{
					throw new Exception("Failed to obtain ISwapChainPanelNative interface");
				}

				if (InitializeRendererCommand.CanExecute(null))
				{
					InitializeRendererCommand.Execute(null);
				}

				// 获取交换链并设置
				_swapChain = ShadeFlowNative.ShadeFlow_GetSwapChain();
				if (_swapChain != IntPtr.Zero)
				{
					_swapChainPanelNative.SetSwapChain(_swapChain);
					_isInitialized = true;
				}
				else
				{
					throw new Exception("Failed to get swap chain");
				}
			}
			catch (Exception ex)
			{
				System.Diagnostics.Debug.WriteLine($"Error initializing swap chain: {ex.Message}");
				Cleanup();
			}
		}

		private void OnFirstTimeSizeChanged(object sender, SizeChangedEventArgs e)
		{
			if (e.NewSize.Width > 0 && e.NewSize.Height > 0)
			{
				SizeChanged -= OnFirstTimeSizeChanged;
				_ = InitializeSwapChainAsync();
			}
		}

		private void UpdateSwapChainSize()
		{
			if (_isDisposed || ActualWidth <= 0 || ActualHeight <= 0 || ResizeRendererCommand == null) return;

			try
			{
				if (ResizeRendererCommand.CanExecute(null))
				{
					ResizeRendererCommand.Execute(null);
				}
			}
			catch (Exception ex)
			{
				System.Diagnostics.Debug.WriteLine($"Error updating swap chain size: {ex.Message}");
			}
		}


		private void Cleanup()
		{
			if (_isDisposed) return;

			_isDisposed = true;
			_isInitialized = false;

			try
			{
				if (_swapChainPanelNative != null)
				{
					_swapChainPanelNative.SetSwapChain(IntPtr.Zero);
					_swapChainPanelNative = null;
				}

				if (CleanupRendererCommand?.CanExecute(null) == true)
				{
					CleanupRendererCommand.Execute(null);
				}
				_swapChain = IntPtr.Zero;

				Loaded -= OnLoaded;
				Unloaded -= OnUnloaded;
				SizeChanged -= OnSizeChanged;
			}
			catch (Exception ex)
			{
				System.Diagnostics.Debug.WriteLine($"Error during cleanup: {ex.Message}");
			}
		}
	}
}