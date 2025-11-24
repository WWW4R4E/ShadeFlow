using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using ShadeFlow.Models;
using System.ComponentModel;
using Windows.Foundation;

namespace ShadeFlow.Controls
{
    public sealed partial class ConnectionLine : UserControl
    {
        public ConnectionLine()
        {
            this.InitializeComponent();
        }

        public static readonly DependencyProperty ConnectionProperty =
            DependencyProperty.Register(nameof(Connection), typeof(Connection), typeof(ConnectionLine), new PropertyMetadata(null, OnConnectionChanged));

        public Connection Connection
        {
            get { return (Connection)GetValue(ConnectionProperty); }
            set { SetValue(ConnectionProperty, value); }
        }

        private static void OnConnectionChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var control = (ConnectionLine)d;
            if (e.OldValue is Connection oldConnection)
            {
                oldConnection.Source.PropertyChanged -= control.OnPortPropertyChanged;
                oldConnection.Target.PropertyChanged -= control.OnPortPropertyChanged;
            }

            if (e.NewValue is Connection newConnection)
            {
                newConnection.Source.PropertyChanged += control.OnPortPropertyChanged;
                newConnection.Target.PropertyChanged += control.OnPortPropertyChanged;
            }

            control.UpdateLine();
        }

        private void OnPortPropertyChanged(object sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(Port.Position))
            {
                UpdateLine();
            }
        }

        private void UpdateLine()
        {
            if (Connection != null)
            {
                var startPoint = new Point(Connection.Source.Position.X, Connection.Source.Position.Y);
                var endPoint = new Point(Connection.Target.Position.X, Connection.Target.Position.Y);
                
                // 计算控制点，使连线呈现弯曲效果
                double tangentLength = System.Math.Abs(endPoint.X - startPoint.X) * 0.8;
                if (tangentLength < 50) tangentLength = 50;
                
                var controlPoint1 = new Point(startPoint.X + tangentLength, startPoint.Y);
                var controlPoint2 = new Point(endPoint.X - tangentLength, endPoint.Y);

                // 创建贝塞尔曲线
                var bezierSegment = new BezierSegment
                {
                    Point1 = controlPoint1,
                    Point2 = controlPoint2,
                    Point3 = endPoint
                };

                var pathSegmentCollection = new PathSegmentCollection { bezierSegment };

                var pathFigure = new PathFigure
                {
                    StartPoint = startPoint,
                    Segments = pathSegmentCollection
                };

                var pathFigureCollection = new PathFigureCollection { pathFigure };

                LineElement.Data = new PathGeometry { Figures = pathFigureCollection };
            }
        }
    }
}