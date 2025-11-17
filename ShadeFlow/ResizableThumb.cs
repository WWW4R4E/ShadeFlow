// ResizableThumb.cs
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using System;
using Windows.UI;

namespace ShadeFlow
{
	public class ResizableThumb : Grid
	{
		private Ellipse _centerVisual;
		private bool _isHovering = false;

		public InputCursor Cursor
		{
			get => ProtectedCursor;
			set => ProtectedCursor = value;
		}

		public enum ThumbOrientation
		{
			Vertical,
			Horizontal
		}

		// 定义Orientation依赖属性
		public static readonly DependencyProperty OrientationProperty =
			DependencyProperty.Register(
				nameof(Orientation),
				typeof(ThumbOrientation),
				typeof(ResizableThumb),
				new PropertyMetadata(ThumbOrientation.Vertical, OnOrientationChanged));

		public ThumbOrientation Orientation
		{
			get { return (ThumbOrientation)GetValue(OrientationProperty); }
			set { SetValue(OrientationProperty, value); }
		}

		public ResizableThumb()
		{
			// 根据方向设置默认样式
			UpdateStyleBasedOnOrientation();

			// 创建中心可视化元素
			CreateCenterVisual();

			// 注册指针事件
			PointerEntered += ResizableThumb_PointerEntered;
			PointerExited += ResizableThumb_PointerExited;
			PointerPressed += ResizableThumb_PointerPressed;
			PointerReleased += ResizableThumb_PointerReleased;
		}

		private static void OnOrientationChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
		{
			var thumb = (ResizableThumb)d;
			thumb.UpdateStyleBasedOnOrientation();
			thumb.UpdateCenterVisual();
		}

		private void UpdateStyleBasedOnOrientation()
		{
			if (Orientation == ThumbOrientation.Vertical)
			{
				Height = 5;
				Width = double.NaN;
				HorizontalAlignment = HorizontalAlignment.Stretch;
				VerticalAlignment = VerticalAlignment.Top;
			}
			else
			{
				// 水平方向：细长竖条
				Width = 5;
				Height = double.NaN;
				VerticalAlignment = VerticalAlignment.Stretch;
				HorizontalAlignment = HorizontalAlignment.Left;
			}

			Background = new SolidColorBrush(Colors.Gray);
		}

		private void CreateCenterVisual()
		{
			_centerVisual = new Ellipse
			{
				Fill = new SolidColorBrush(Colors.White),
				HorizontalAlignment = HorizontalAlignment.Center,
				VerticalAlignment = VerticalAlignment.Center,
				Opacity = 0
			};

			Children.Add(_centerVisual);
			UpdateCenterVisual();
		}

		private void UpdateCenterVisual()
		{
			if (_centerVisual == null) return;

			if (Orientation == ThumbOrientation.Vertical)
			{
				_centerVisual.Width = 1000;
				_centerVisual.Height = 10;
			}
			else
			{
				_centerVisual.Width = 10;
				_centerVisual.Height = 1000;
			}
		}

		private void AnimateIn()
		{
			if (_centerVisual == null || _isHovering) return;
			_isHovering = true;

			// 创建动画
			var storyboard = new Storyboard();

			// 淡入动画
			var fadeInAnimation = new DoubleAnimation
			{
				From = 0.0,
				To = 1.0,
				Duration = new Duration(TimeSpan.FromMilliseconds(500))
			};
			Storyboard.SetTarget(fadeInAnimation, _centerVisual);
			Storyboard.SetTargetProperty(fadeInAnimation, "Opacity");
			storyboard.Children.Add(fadeInAnimation);

			// 变形动画
			if (Orientation != ThumbOrientation.Vertical)
			{
				// 垂直方向：圆形变椭圆（水平拉伸）
				var widthAnimation = new DoubleAnimation
				{
					From = 10.0,
					To = 1000.0,
					Duration = new Duration(TimeSpan.FromMilliseconds(500)),
					BeginTime = TimeSpan.FromMilliseconds(200)
				};
				Storyboard.SetTarget(widthAnimation, _centerVisual);
				Storyboard.SetTargetProperty(widthAnimation, "Height");
				storyboard.Children.Add(widthAnimation);
			}
			else
			{
				// 水平方向：圆形变椭圆（垂直拉伸）
				var heightAnimation = new DoubleAnimation
				{
					From = 10.0,
					To = 1000.0,
					Duration = new Duration(TimeSpan.FromMilliseconds(500)),
					BeginTime = TimeSpan.FromMilliseconds(200)
				};
				Storyboard.SetTarget(heightAnimation, _centerVisual);
				Storyboard.SetTargetProperty(heightAnimation, "Width");
				storyboard.Children.Add(heightAnimation);
			}

			storyboard.Begin();
		}

		private void AnimateOut()
		{
			if (_centerVisual == null || !_isHovering) return;
			_isHovering = false;

			// 创建动画
			var storyboard = new Storyboard();

			// 淡出动画
			var fadeOutAnimation = new DoubleAnimation
			{
				From = 1.0,
				To = 0.0,
				Duration = new Duration(TimeSpan.FromMilliseconds(500))
			};
			Storyboard.SetTarget(fadeOutAnimation, _centerVisual);
			Storyboard.SetTargetProperty(fadeOutAnimation, "Opacity");
			storyboard.Children.Add(fadeOutAnimation);

			// 恢复原始尺寸
			if (Orientation == ThumbOrientation.Vertical)
			{
				var widthAnimation = new DoubleAnimation
				{
					From = 60.0,
					To = 10.0,
					Duration = new Duration(TimeSpan.FromMilliseconds(500))
				};
				Storyboard.SetTarget(widthAnimation, _centerVisual);
				Storyboard.SetTargetProperty(widthAnimation, "Width");
				storyboard.Children.Add(widthAnimation);
			}
			else
			{
				var heightAnimation = new DoubleAnimation
				{
					From = 60.0,
					To = 10.0,
					Duration = new Duration(TimeSpan.FromMilliseconds(500))
				};
				Storyboard.SetTarget(heightAnimation, _centerVisual);
				Storyboard.SetTargetProperty(heightAnimation, "Height");
				storyboard.Children.Add(heightAnimation);
			}

			storyboard.Begin();
		}

		private void ResizableThumb_PointerEntered(object sender, PointerRoutedEventArgs e)
		{
			// 根据方向设置不同的光标
			if (Orientation == ThumbOrientation.Vertical)
			{
				Cursor = InputSystemCursor.Create(InputSystemCursorShape.SizeNorthSouth);
			}
			else
			{
				Cursor = InputSystemCursor.Create(InputSystemCursorShape.SizeWestEast);
			}

			AnimateIn();
		}

		private void ResizableThumb_PointerExited(object sender, PointerRoutedEventArgs e)
		{
			Cursor = InputSystemCursor.Create(InputSystemCursorShape.Arrow);
			AnimateOut();
		}

		private void ResizableThumb_PointerPressed(object sender, PointerRoutedEventArgs e)
		{
			if (_centerVisual != null)
			{
				_centerVisual.Fill = new SolidColorBrush(Colors.LightGray);
			}
		}

		private void ResizableThumb_PointerReleased(object sender, PointerRoutedEventArgs e)
		{
			if (_centerVisual != null)
			{
				_centerVisual.Fill = new SolidColorBrush(Colors.White);
			}
		}
	}
}