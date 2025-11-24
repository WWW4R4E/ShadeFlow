using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using ShadeFlow.Models;
using Windows.Foundation;
using System.Windows.Input;

namespace ShadeFlow.Controls
{
    public sealed partial class ShadeNode : UserControl
    {
        private Point _lastPoint;
        private bool _isDragging = false;
        private bool _isConnecting = false;
        public ShadeNode()
        {
            InitializeComponent();
            this.Loaded += ShadeNode_Loaded;
        }

        private T FindVisualParent<T>(DependencyObject child) where T : DependencyObject
        {
            var parentObject = VisualTreeHelper.GetParent(child);

            if (parentObject == null) return null;

            if (parentObject is T parent)
                return parent;

            return FindVisualParent<T>(parentObject);
        }

        private Canvas GetCanvas()
        {
            return FindVisualParent<Canvas>(this);
        }

        private void ShadeNode_Loaded(object sender, RoutedEventArgs e)
        {
            Node.Visual = this;
            UpdatePosition();
            DispatcherQueue.TryEnqueue(() => UpdatePortPositions());
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
            else if (e.PropertyName == nameof(Node.ZIndex))
            {
                UpdateZIndex();
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
                UpdatePortPositions();
            }
        }

        private void UpdatePortPositions()
        {
            if (Node == null || GetCanvas() == null) return;

            for (int i = 0; i < Node.InputPorts.Count; i++)
            {
                var port = Node.InputPorts[i];
                var element = GetPortElement(i, true);
                if (element != null)
                {
                    var centerPoint = new Point(element.ActualWidth / 2, element.ActualHeight / 2);
                    var transform = element.TransformToVisual(GetCanvas());
                    var position = transform.TransformPoint(centerPoint);
                    port.Position = position;
                }
            }

            for (int i = 0; i < Node.OutputPorts.Count; i++)
            {
                var port = Node.OutputPorts[i];
                var element = GetPortElement(i, false);
                if (element != null)
                {
                    var centerPoint = new Point(element.ActualWidth / 2, element.ActualHeight / 2);
                    var transform = element.TransformToVisual(GetCanvas());
                    var position = transform.TransformPoint(centerPoint);
                    port.Position = position;
                }
            }
        }

        private Ellipse GetPortElement(int index, bool isInput)
        {
            var panel = isInput ? 
                (this.FindName("InputPortsControl") as ItemsControl)?.ItemsPanelRoot :
                (this.FindName("OutputPortsControl") as ItemsControl)?.ItemsPanelRoot;
                
            if (panel is Panel itemsPanel && index < itemsPanel.Children.Count)
            {
                var container = itemsPanel.Children[index];
                return FindVisualChild<Ellipse>(container);
            }
            
            return null;
        }

        private T FindVisualChild<T>(DependencyObject parent) where T : DependencyObject
        {
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            {
                var child = VisualTreeHelper.GetChild(parent, i);
                if (child is T typedChild)
                    return typedChild;

                var childOfChild = FindVisualChild<T>(child);
                if (childOfChild != null)
                    return childOfChild;
            }
            return null;
        }

        private void UpdateZIndex()
        {
            if (Node == null) return;

            var parent = VisualTreeHelper.GetParent(this) as UIElement;
            if (parent != null)
            {
                Canvas.SetZIndex(parent, Node.ZIndex);
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
                BringNodeToFrontCommand?.Execute(Node);
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

                var nodeEditor = FindVisualParent<NodeEditor>(this);
                var scaleFactor = nodeEditor?.ZoomFactor ?? 1.0;

                Node.MoveBy(deltaX / scaleFactor, deltaY / scaleFactor);

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


		private void InputPort_PointerPressed(object sender, PointerRoutedEventArgs e)
		{
			if (sender is Ellipse el && el.Tag is Port port)
			{
				_isConnecting = true;
				var centerPoint = new Point(el.ActualWidth / 2, el.ActualHeight / 2);
				var transform = el.TransformToVisual(GetCanvas());
				var position = transform.TransformPoint(centerPoint);
				
				if (port.Connections.Count > 0) CancelConnectCommand?.Execute(position);
				else ConnectStartCommand?.Execute(position);
				el.CapturePointer(e.Pointer);
			}

			e.Handled = true;
		}


		private void InputPort_PointerMoved(object sender, PointerRoutedEventArgs e)
		{
			if (_isConnecting && sender is Ellipse el && el.Tag is Port port)
			{
				var transform = el.TransformToVisual(GetCanvas());
				var position = transform.TransformPoint(e.GetCurrentPoint(el).Position);
				ConnectMoveCommand?.Execute(position);
				el.CapturePointer(e.Pointer);
			}

			e.Handled = true;
		}

		private void InputPort_PointerReleased(object sender, PointerRoutedEventArgs e)
		{
			if (_isConnecting && sender is Ellipse el && el.Tag is Port port)
			{
				var centerPoint = new Point(el.ActualWidth / 2, el.ActualHeight / 2);
				var transform = el.TransformToVisual(GetCanvas());
				var position = transform.TransformPoint(centerPoint);
				ConnectEndCommand?.Execute(position);
				_isConnecting = false;
				el.ReleasePointerCapture(e.Pointer);
			}


			e.Handled = true;
		}

		private void OutputPort_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            if (sender is Ellipse el && el.Tag is Port port)
            {
                _isConnecting = true;
                var centerPoint = new Point(el.ActualWidth / 2, el.ActualHeight / 2);
                var transform = el.TransformToVisual(GetCanvas());
                var position = transform.TransformPoint(centerPoint);
                ConnectStartCommand?.Execute(position);
            }

            e.Handled = true;
        }

        private void OutputPort_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            if (_isConnecting && sender is Ellipse el && el.Tag is Port port)
            {
                var transform = el.TransformToVisual(GetCanvas());
                var position = transform.TransformPoint(e.GetCurrentPoint(el).Position);
                ConnectMoveCommand?.Execute(position);
                el.CapturePointer(e.Pointer);
            }

            e.Handled = true;
        }

        private void OutputPort_PointerReleased(object sender, PointerRoutedEventArgs e)
        {
            if (_isConnecting && sender is Ellipse el && el.Tag is Port port)
            {
                var centerPoint = new Point(el.ActualWidth / 2, el.ActualHeight / 2);
                var transform = el.TransformToVisual(GetCanvas());
                var position = transform.TransformPoint(centerPoint);
                ConnectEndCommand?.Execute(position);
                _isConnecting = false;
                el.ReleasePointerCapture(e.Pointer);
            }

            e.Handled = true;
        }

        #region
        public static readonly DependencyProperty NodeProperty =
            DependencyProperty.Register("Node", typeof(NodeBase), typeof(ShadeNode), new PropertyMetadata(null, OnNodeChanged));

        public NodeBase Node
        {
            get { return (NodeBase)GetValue(NodeProperty); }
            set { SetValue(NodeProperty, value); }
        }

        public static readonly DependencyProperty BringNodeToFrontCommandProperty =
            DependencyProperty.Register(nameof(BringNodeToFrontCommand), typeof(ICommand), typeof(ShadeNode), new PropertyMetadata(null));

        public ICommand BringNodeToFrontCommand
        {
            get => (ICommand)GetValue(BringNodeToFrontCommandProperty);
            set => SetValue(BringNodeToFrontCommandProperty, value);
        }

        public ICommand ConnectStartCommand
        {
            get { return (ICommand)GetValue(ConnectStartCommandProperty); }
            set { SetValue(ConnectStartCommandProperty, value); }
        }

        public static readonly DependencyProperty ConnectStartCommandProperty =
            DependencyProperty.Register("ConnectStartCommand", typeof(ICommand), typeof(ShadeNode), new PropertyMetadata(null));

        public ICommand ConnectMoveCommand
        {
            get { return (ICommand)GetValue(ConnectMoveCommandProperty); }
            set { SetValue(ConnectMoveCommandProperty, value); }
        }

        public static readonly DependencyProperty ConnectMoveCommandProperty =
            DependencyProperty.Register("ConnectMoveCommand", typeof(ICommand), typeof(ShadeNode), new PropertyMetadata(null));

        public ICommand ConnectEndCommand
        {
            get { return (ICommand)GetValue(ConnectEndCommandProperty); }
            set { SetValue(ConnectEndCommandProperty, value); }
        }

        public static readonly DependencyProperty ConnectEndCommandProperty =
            DependencyProperty.Register("ConnectEndCommand", typeof(ICommand), typeof(ShadeNode), new PropertyMetadata(null));
        
        public ICommand CancelConnectCommand
        {
            get { return (ICommand)GetValue(CancelConnectCommandProperty); }
            set { SetValue(CancelConnectCommandProperty, value); }
        }

        public static readonly DependencyProperty CancelConnectCommandProperty =
            DependencyProperty.Register("CancelConnectCommand", typeof(ICommand), typeof(ShadeNode), new PropertyMetadata(null));
        
        #endregion

    }
}