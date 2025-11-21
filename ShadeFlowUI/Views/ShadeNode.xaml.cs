using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using ShadeFlow.Models;
using Windows.Foundation;

namespace ShadeFlow.Views
{
    public sealed partial class ShadeNode : UserControl
    {
        private Point _lastPoint;
        private bool _isDragging = false;

        public static readonly DependencyProperty NodeProperty =
            DependencyProperty.Register("Node", typeof(NodeBase), typeof(ShadeNode), new PropertyMetadata(null, OnNodeChanged));

        public NodeBase Node
        {
            get { return (NodeBase)GetValue(NodeProperty); }
            set { SetValue(NodeProperty, value); }
        }
        public ShadeNode()
        {
            InitializeComponent();
            this.Loaded += ShadeNode_Loaded;
        }

        private void ShadeNode_Loaded(object sender, RoutedEventArgs e)
        {
            UpdatePosition(); 
        }

        private static void OnNodeChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var control = (ShadeNode)d;
            var oldNode = e.OldValue as NodeBase;
            var newNode = e.NewValue as NodeBase;

            if (oldNode != null)
            {
                oldNode.PropertyChanged -= control.Node_PropertyChanged;
            }

            if (newNode != null)
            {
                newNode.PropertyChanged += control.Node_PropertyChanged;
            }
            control.Bindings.Update();
        }

        private void Node_PropertyChanged(object sender, System.ComponentModel.PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(Node.X) || e.PropertyName == nameof(Node.Y))
            {
                UpdatePosition();
            }

            if (DispatcherQueue.HasThreadAccess)
                Bindings.Update();
            else
                DispatcherQueue.TryEnqueue(() => Bindings.Update());
        }

        private void UpdatePosition()
        {
            if (Node == null) return;

            var parent = VisualTreeHelper.GetParent(this) as UIElement;
            {
                Canvas.SetLeft(parent, Node.X);
                Canvas.SetTop(parent, Node.Y);
            }
        }
        private void TitleBar_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            var element = (UIElement)sender;

            var point = e.GetCurrentPoint(null);

            if (point.Properties.IsLeftButtonPressed)
            {
                _lastPoint = point.Position;
                _isDragging = true;

                element.CapturePointer(e.Pointer);

                e.Handled = true;
            }
        }

        private void TitleBar_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            if (_isDragging)
            {
                var currentPoint = e.GetCurrentPoint(null);

                var deltaX = currentPoint.Position.X - _lastPoint.X;
                var deltaY = currentPoint.Position.Y - _lastPoint.Y;

                // TODO 修复缩放偏移量 
                Node.MoveBy(deltaX, deltaY);

                _lastPoint = currentPoint.Position;

                e.Handled = true;
            }
        }

        private void TitleBar_PointerReleased(object sender, PointerRoutedEventArgs e)
        {
            if (_isDragging)
            {
                _isDragging = false;
                ((UIElement)sender).ReleasePointerCapture(e.Pointer);
                e.Handled = true;
            }
        }
    }
}