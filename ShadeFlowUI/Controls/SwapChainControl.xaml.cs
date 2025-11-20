using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using ShadeFlow.Natives;
using ShadeFlow.ViewModels;
using System;
using System.Threading.Tasks;
using WinRT;

namespace ShadeFlow.Controls
{
	public sealed partial class SwapChainControl : SwapChainPanel
	{
		private ISwapChainPanelNative _swapChainPanelNative;
		private IntPtr _swapChain = IntPtr.Zero;
		private bool _isInitialized = false;
		private bool _isDisposed = false;

		public static readonly DependencyProperty ViewModelProperty =
			DependencyProperty.Register(nameof(ViewModel), typeof(HomePageViewModel), typeof(SwapChainControl),
				new PropertyMetadata(null, OnViewModelChanged));

		public HomePageViewModel ViewModel
		{
			get => (HomePageViewModel)GetValue(ViewModelProperty);
			set => SetValue(ViewModelProperty, value);
		}

		public SwapChainControl()
		{
			InitializeComponent();
		}

		private static void OnViewModelChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
		{
			if (d is SwapChainControl control)
			{
				if (e.OldValue is HomePageViewModel oldViewModel)
				{
					oldViewModel.PropertyChanged -= control.OnViewModelPropertyChanged;
				}

				if (e.NewValue is HomePageViewModel newViewModel)
				{
					newViewModel.PropertyChanged += control.OnViewModelPropertyChanged;
				}
			}
		}

		private void OnViewModelPropertyChanged(object sender, System.ComponentModel.PropertyChangedEventArgs e)
		{
			if (e.PropertyName == nameof(HomePageViewModel.RenderWidth) ||
				e.PropertyName == nameof(HomePageViewModel.RenderHeight))
			{
				if (_isInitialized && !_isDisposed)
				{
					UpdateSwapChainSize();
				}
			}
		}

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
			if (_isInitialized || ViewModel == null) return;

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

				// 使用ViewModel初始化渲染器
				await ViewModel.InitializeRendererAsync(
					(int)ActualWidth,
					(int)ActualHeight,
					XamlRoot.RasterizationScale);

				// 获取交换链并设置
				_swapChain = ViewModel.GetSwapChain();
				if (_swapChain != IntPtr.Zero)
				{
					_swapChainPanelNative.SetSwapChain(_swapChain);
					_isInitialized = true;
				}
				else
				{
					throw new Exception("Failed to get swap chain from ViewModel");
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
			if (_isDisposed || ActualWidth <= 0 || ActualHeight <= 0) return;

			try
			{
				ViewModel?.ResizeRenderer((int)ActualWidth, (int)ActualHeight);
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

				ViewModel?.Cleanup();
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