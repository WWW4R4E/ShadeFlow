using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using System;
using Windows.Foundation;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace ShadeFlow
{
    /// <summary>
    /// An empty page that can be used on its own or navigated to within a Frame.
    /// </summary>
    public sealed partial class HomePage : Page
    {
        private bool isDragging = false;
        private bool isHorizontalDragging = false;
        private Point startPoint;
        private Point startHorizontalPoint;
        
        public HomePage()
        {
            InitializeComponent();
        }

        private void ResizeThumb_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            var thumb = sender as ResizableThumb;
            if (thumb != null)
            {
                startPoint = e.GetCurrentPoint(thumb).Position;
                isDragging = true;
                thumb.CapturePointer(e.Pointer);
            }
        }

        private void ResizeThumb_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            if (!isDragging) return;

            var thumb = sender as ResizableThumb;
            if (thumb != null)
            {
                var currentPosition = e.GetCurrentPoint(thumb).Position;
                var delta = currentPosition.Y - startPoint.Y;
                renderPreview.Height += delta;
                nodeEditor.Height -= delta;
            }
        }

        private void ResizeThumb_PointerReleased(object sender, PointerRoutedEventArgs e)
        {
            var thumb = sender as ResizableThumb;
            if (thumb != null)
            {
                isDragging = false;
                thumb.ReleasePointerCapture(e.Pointer);
            }
        }
        
        private void Page_Loaded(object sender, RoutedEventArgs e)
        {
            var Height = this.ActualHeight / 2;
            renderPreview.Height = Height;
            nodeEditor.Height = Height;
            var Width = this.ActualWidth;
            LeftPanel.Width = Width- 350;
            propertyPanel.Width = 350;
        }

        private void HorizontalResizeThumb_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            var thumb = sender as ResizableThumb;
            if (thumb != null)
            {
                startHorizontalPoint = e.GetCurrentPoint(thumb).Position;
                isHorizontalDragging = true;
                thumb.CapturePointer(e.Pointer);
            }
        }

        private void HorizontalResizeThumb_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            if (!isHorizontalDragging) return;

            var thumb = sender as ResizableThumb;
            if (thumb != null)
            {
                var currentPosition = e.GetCurrentPoint(thumb).Position;
                var delta = currentPosition.X - startHorizontalPoint.X;

                LeftPanel.Width += delta;
                propertyPanel.Width -= delta;
            }
        }

        private void HorizontalResizeThumb_PointerReleased(object sender, PointerRoutedEventArgs e)
        {
            var thumb = sender as ResizableThumb;
            if (thumb != null)
            {
                isHorizontalDragging = false;
                thumb.ReleasePointerCapture(e.Pointer);
            }
        }
    }
}