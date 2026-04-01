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
		private bool _isVertical1Dragging = false;
		private bool _isVertical2Dragging = false;

		public HomePageViewModel ViewModel { get; } = new HomePageViewModel();

		public HomePage()
		{
			InitializeComponent();
		}

		private void UpdateHoverZones()
		{
			if (RootGrid.ActualWidth == 0 || RootGrid.ActualHeight == 0) return;

			double horizontalY = TopRow.ActualHeight + HorizontalVisualLine.ActualHeight / 2;
			HorizontalHoverZone.Margin = new Thickness(0, horizontalY - HorizontalHoverZone.Height / 2, 0, 0);

			double vertical1X = LeftColumn.ActualWidth + VerticalVisualLine1.ActualWidth / 2 - VerticalHoverZone1.Width / 2;
			double vertical1Y = (RootGrid.ActualHeight - VerticalHoverZone1.Height) / 2;
			VerticalHoverZone1.Margin = new Thickness(vertical1X, vertical1Y, 0, 0);

			double vertical2X = RightColumn.ActualWidth + VerticalVisualLine1.ActualWidth / 2 - VerticalHoverZone2.ActualWidth / 2;
      double vertical2Y = (RootGrid.ActualHeight - VerticalHoverZone2.Height) / 2;
			VerticalHoverZone2.Margin = new Thickness(0, 0,vertical2X, vertical2Y);
		}

		private void Page_SizeChanged(object sender, SizeChangedEventArgs e)
		{
			UpdateHoverZones();
            UpdateViewModelRenderSize();
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

		private void VerticalHoverZone2_PointerMoved(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical2Dragging) return;
			var pos = e.GetCurrentPoint(VerticalHoverZone2).Position;
			double distToCenter = Math.Abs(pos.X - VerticalHoverZone2.Width / 2);
			double maxDist = VerticalHoverZone2.Width / 2;

			double normalizedDist = Math.Min(1.0, distToCenter / maxDist);
			double ratio = 1.0 - normalizedDist * normalizedDist;

			double targetHeight = 120 + ratio * (250 - 120);
			VerticalVisualLine2.Height = targetHeight;
			if (distToCenter <= 3)
			{
				VerticalVisualLine2.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorPrimaryBrush"];
			}
			else
			{
				VerticalVisualLine2.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorTertiaryBrush"];
			}
		}
		private void VerticalHoverZone2_PointerPressed(object sender, PointerRoutedEventArgs e)
		{
			var pos = e.GetCurrentPoint(VerticalHoverZone2).Position;
			if (Math.Abs(pos.X - VerticalHoverZone2.Width / 2) <= 3)
			{
				_isVertical2Dragging = true;
				VerticalHoverZone2.CapturePointer(e.Pointer);
				e.Handled = true;
			}
		}

		private void VerticalHoverZone2_PointerReleased(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical2Dragging)
			{
				_isVertical2Dragging = false;
				VerticalHoverZone2.ReleasePointerCapture(e.Pointer);
				UpdateHoverZones();
				e.Handled = true;
			}
		}

		private void VerticalHoverZone2_PointerExited(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical2Dragging) return;
			VerticalVisualLine2.Height = 120;
		}

		private void VerticalHoverZone2_PointerEntered(object sender, PointerRoutedEventArgs e)
		{
			VerticalHoverZone2_PointerMoved(sender, e);
		}

		private void VerticalHoverZone1_PointerMoved(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical1Dragging) return;
			var pos = e.GetCurrentPoint(VerticalHoverZone1).Position;
			double distToCenter = Math.Abs(pos.X - VerticalHoverZone1.Width / 2);
			double maxDist = VerticalHoverZone1.Width / 2;

			double normalizedDist = Math.Min(1.0, distToCenter / maxDist);
			double ratio = 1.0 - normalizedDist * normalizedDist;

			double targetHeight = 120 + ratio * (250 - 120);
			VerticalVisualLine1.Height = targetHeight;
			if (distToCenter <= 3)
			{
				VerticalVisualLine1.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorPrimaryBrush"];
			}
			else
			{
				VerticalVisualLine1.Background = (SolidColorBrush)Application.Current.Resources["TextFillColorTertiaryBrush"];
			}
		}

		private void VerticalHoverZone1_PointerPressed(object sender, PointerRoutedEventArgs e)
		{
			var pos = e.GetCurrentPoint(VerticalHoverZone1).Position;
			if (Math.Abs(pos.X - VerticalHoverZone1.Width / 2) <= 3)
			{
				_isVertical1Dragging = true;
				VerticalHoverZone1.CapturePointer(e.Pointer);
				e.Handled = true;
			}
		}

		private void VerticalHoverZone1_PointerReleased(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical1Dragging)
			{
				_isVertical1Dragging = false;
				VerticalHoverZone1.ReleasePointerCapture(e.Pointer);
				UpdateHoverZones();
				e.Handled = true;
			}
		}

		private void VerticalHoverZone1_PointerExited(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical1Dragging) return;
			VerticalVisualLine1.Height = 120;
		}

		private void VerticalHoverZone1_PointerEntered(object sender, PointerRoutedEventArgs e)
		{
			VerticalHoverZone1_PointerMoved(sender, e);
		}

		private void VerticalHoverZone1_PointerMoved_Drag(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical1Dragging)
			{
				Vertical1DragUpdate(e);
				e.Handled = true;
			}
			else
			{
				VerticalHoverZone1_PointerMoved(sender, e);
			}
		}

		private void Vertical1DragUpdate(PointerRoutedEventArgs e)
		{
			var globalPos = e.GetCurrentPoint(RootGrid).Position;
			const double minSize = 0;

			double left = Math.Max(minSize, globalPos.X);
			double center = RootGrid.ActualWidth - globalPos.X - RightColumn.ActualWidth - VerticalVisualLine1.ActualWidth - VerticalVisualLine2.ActualWidth;

			if (center < minSize)
			{
				center = minSize;
			}

			LeftColumn.Width = new GridLength(Math.Max(minSize, left));
			CenterColumn.Width = new GridLength(Math.Max(minSize, center));

			UpdateViewModelRenderSize();
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

		private void VerticalHoverZone2_PointerMoved_Drag(object sender, PointerRoutedEventArgs e)
		{
			if (_isVertical2Dragging)
			{
				Vertical2DragUpdate(e);
				e.Handled = true;
			}
			else
			{
				VerticalHoverZone2_PointerMoved(sender, e);
			}
		}

		private void Vertical2DragUpdate(PointerRoutedEventArgs e)
		{
			var globalPos = e.GetCurrentPoint(RootGrid).Position;
			const double minSize = 0;
			double totalW = RootGrid.ActualWidth;
			double splitterW = VerticalVisualLine2.ActualWidth;

			double center = Math.Max(minSize, globalPos.X - LeftColumn.ActualWidth - splitterW);
			double right = totalW - globalPos.X - splitterW;

			CenterColumn.Width = new GridLength(Math.Max(minSize, center));
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
	}
}