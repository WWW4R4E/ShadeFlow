using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using ShadeFlow.ViewModels;
using System;

namespace ShadeFlow.Views
{
	public sealed partial class HomePage : Page
	{
		private bool _isHorizontalDragging = false;
		private bool _isVerticalDragging = false;

		public HomePageViewModel ViewModel { get; } = new HomePageViewModel();

		public HomePage()
		{
			InitializeComponent();
		}

		private void UpdateHoverZones()
		{
			if (RootGrid.ActualWidth == 0 || RootGrid.ActualHeight == 0) return;

			double horizontalY = TopRow.ActualHeight + HorizontalVisualLine.ActualHeight / 2;
			double horizontalX = (RootGrid.ActualWidth - HorizontalHoverZone.Width - RightColumn.ActualWidth) / 2;
			HorizontalHoverZone.Margin = new Thickness(horizontalX, horizontalY - HorizontalHoverZone.Height / 2, 0, 0);

			double verticalX = LeftColumn.ActualWidth + VerticalVisualLine.ActualWidth / 2;
			double verticalY = (RootGrid.ActualHeight - VerticalHoverZone.Height) / 2;
			VerticalHoverZone.Margin = new Thickness(verticalX - VerticalHoverZone.Width / 2, verticalY, 0, 0);
		}

		private void Page_Loaded(object sender, RoutedEventArgs e)
		{
			UpdateHoverZones();
			UpdateViewModelRenderSize();
		}

		private void Page_SizeChanged(object sender, SizeChangedEventArgs e)
		{
			UpdateHoverZones();
		}

		private void HorizontalHoverZone_PointerMoved(object sender, PointerRoutedEventArgs e)
		{
			if (_isHorizontalDragging) return;
			var pos = e.GetCurrentPoint(HorizontalHoverZone).Position;
			double distToCenter = Math.Abs(pos.Y - HorizontalHoverZone.Height / 2);
			double maxDist = HorizontalHoverZone.Height / 2;

			double normalizedDist = Math.Min(1.0, distToCenter / maxDist);
			double ratio = 1.0 - normalizedDist * normalizedDist;

			double targetWidth = 120 + ratio * (250 - 120);
			HorizontalVisualLine.Width = targetWidth;
			if (distToCenter <= 3)
			{
				HorizontalVisualLine.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorPrimaryBrush"];
			}
			else
			{
				HorizontalVisualLine.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorTertiaryBrush"];
			}
		}

		private void HorizontalHoverZone_PointerPressed(object sender, PointerRoutedEventArgs e)
		{
			var pos = e.GetCurrentPoint(HorizontalHoverZone).Position;
			if (Math.Abs(pos.Y - HorizontalHoverZone.Height / 2) <= 3)
			{
				_isHorizontalDragging = true;
				HorizontalHoverZone.CapturePointer(e.Pointer);
				e.Handled = true;
			}
    }

		private void HorizontalHoverZone_PointerReleased(object sender, PointerRoutedEventArgs e)
		{
			if (_isHorizontalDragging)
			{
				_isHorizontalDragging = false;
				HorizontalHoverZone.ReleasePointerCapture(e.Pointer);
				UpdateHoverZones();
				e.Handled = true;
			}
		}

		private void HorizontalHoverZone_PointerExited(object sender, PointerRoutedEventArgs e)
		{
			if (_isHorizontalDragging) return;
			HorizontalVisualLine.Width = 120;
		}

		private void HorizontalHoverZone_PointerEntered(object sender, PointerRoutedEventArgs e)
		{
			HorizontalHoverZone_PointerMoved(sender, e);
		}

		private void HorizontalDragUpdate(PointerRoutedEventArgs e)
		{
			var globalPos = e.GetCurrentPoint(RootGrid).Position;
			const double minSize = 0;
			double totalH = RootGrid.ActualHeight;
			double splitterH = HorizontalVisualLine.ActualHeight;

			double top = Math.Max(minSize, globalPos.Y);
			double bottom = totalH - top - splitterH;
			if (bottom < minSize)
			{
				top = totalH - minSize - splitterH;
				bottom = minSize;
			}

			TopRow.Height = new GridLength(Math.Max(minSize, top));
			BottomRow.Height = new GridLength(Math.Max(minSize, bottom));

			// 更新ViewModel的渲染尺寸
			UpdateViewModelRenderSize();
		}

		private void VerticalHoverZone_PointerMoved(object sender, PointerRoutedEventArgs e)
		{
			if (_isVerticalDragging) return;
			var pos = e.GetCurrentPoint(VerticalHoverZone).Position;
			double distToCenter = Math.Abs(pos.X - VerticalHoverZone.Width / 2);
			double maxDist = VerticalHoverZone.Width / 2;

			// 归一化距离 [0, 1]
			double normalizedDist = Math.Min(1.0, distToCenter / maxDist);

			// 先快后慢：使用 ease-out 效果 → ratio = 1 - normalizedDist^2
			double ratio = 1.0 - normalizedDist * normalizedDist;

			double targetHeight = 120 + ratio * (250 - 120);
			VerticalVisualLine.Height = targetHeight;
			if (distToCenter <= 3)
			{
				VerticalVisualLine.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorPrimaryBrush"];
			}
			else
			{
				VerticalVisualLine.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorTertiaryBrush"];
			}
		}
		private void VerticalHoverZone_PointerPressed(object sender, PointerRoutedEventArgs e)
		{
			var pos = e.GetCurrentPoint(VerticalHoverZone).Position;
			if (Math.Abs(pos.X - VerticalHoverZone.Width / 2) <= 3)
			{
				_isVerticalDragging = true;
				VerticalHoverZone.CapturePointer(e.Pointer);
				e.Handled = true;
			}
		}

		private void VerticalHoverZone_PointerReleased(object sender, PointerRoutedEventArgs e)
		{
			if (_isVerticalDragging)
			{
				_isVerticalDragging = false;
				VerticalHoverZone.ReleasePointerCapture(e.Pointer);
				UpdateHoverZones();
				e.Handled = true;
			}
		}

		private void VerticalHoverZone_PointerExited(object sender, PointerRoutedEventArgs e)
		{
			if (_isVerticalDragging) return;
			VerticalVisualLine.Height = 120;
		}

		private void VerticalHoverZone_PointerEntered(object sender, PointerRoutedEventArgs e)
		{
			VerticalHoverZone_PointerMoved(sender, e);
		}

		private void VerticalDragUpdate(PointerRoutedEventArgs e)
		{
			var globalPos = e.GetCurrentPoint(RootGrid).Position;
			const double minSize = 0;
			double totalW = RootGrid.ActualWidth;
			double splitterW = VerticalVisualLine.ActualWidth;

			double left = Math.Max(minSize, globalPos.X);
			double right = totalW - left - splitterW;
			if (right < minSize)
			{
				left = totalW - minSize - splitterW;
				right = minSize;
			}

			LeftColumn.Width = new GridLength(Math.Max(minSize, left));
			RightColumn.Width = new GridLength(Math.Max(minSize, right));

			UpdateViewModelRenderSize();
		}

		private void UpdateViewModelRenderSize()
		{
			double renderWidth = renderPreview.ActualWidth;
			double renderHeight = renderPreview.ActualHeight;

			if (renderWidth > 0 && renderHeight > 0)
			{
				ViewModel.RenderViewModel.RenderWidth = (int)renderWidth;
				ViewModel.RenderViewModel.RenderHeight = (int)renderHeight;

				if (ViewModel.RenderViewModel.ResizeRendererCommand?.CanExecute(null) == true)
				{
					ViewModel.RenderViewModel.ResizeRendererCommand.Execute(null);
				}
			}
		}

		private void HorizontalHoverZone_PointerMoved_Drag(object sender, PointerRoutedEventArgs e)
		{
			if (_isHorizontalDragging)
			{
				HorizontalDragUpdate(e);
				e.Handled = true;
			}
			else
			{
				HorizontalHoverZone_PointerMoved(sender, e);
			}
		}

		private void VerticalHoverZone_PointerMoved_Drag(object sender, PointerRoutedEventArgs e)
		{
			if (_isVerticalDragging)
			{
				VerticalDragUpdate(e);
				e.Handled = true;
			}
			else
			{
				VerticalHoverZone_PointerMoved(sender, e);
			}
		}
	}
}