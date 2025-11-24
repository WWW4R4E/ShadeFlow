using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ShadeFlow.Controls;
using ShadeFlow.Models;
using ShadeFlow.Utils;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using Windows.Foundation;
using Windows.UI;

namespace ShadeFlow.ViewModels
{
    public partial class NodeEditorViewModel : ObservableObject
    {
        private static readonly NodeEditorViewModel _instance = new NodeEditorViewModel();

        private Port _sourcePort;
        private Port _targetPort;
        public NodeEditor editor;

        #region ObservableProperty

        // 节点集合 - 用于NodeEditor的数据绑定
        [ObservableProperty]
        private ObservableCollection<NodeBase> _nodes = new ObservableCollection<NodeBase>();

        [ObservableProperty]
        private ObservableCollection<Connection> _connections = new ObservableCollection<Connection>();

        // 临时连接线的起点和终点
        [ObservableProperty]
        private Point _tempLineStart;

        [ObservableProperty]
        private Point _tempLineEnd;

        // 是否显示临时连接线
        [ObservableProperty]
        private bool _showTempLine = false;

        private Connection _existingConnection;

        #endregion ObservableProperty

        private NodeEditorViewModel()
        {
            GenerateTestNodes();
        }

        public static NodeEditorViewModel Instance => _instance;

        [RelayCommand]
        private void BringNodeToFront(NodeBase node)
        {
            if (node == null) return;
            int totalNodes = Nodes.Count;
            node.ZIndex = totalNodes;

            foreach (var otherNode in Nodes)
                if (otherNode != node) otherNode.ZIndex--;
        }

        [RelayCommand]
        private void StartConnect(Point point)
        {
            TempLineStart = point;
            TempLineEnd = point;
            ShowTempLine = true;

            Port closestPort = null;
            double closestDistance = double.MaxValue;
            const double SnapRange = 15.0;

            foreach (var node in Nodes)
            {
                foreach (var outputPort in node.OutputPorts)
                {
                    var distance = Math.Sqrt(Math.Pow(point.X - outputPort.Position.X, 2) +
                                           Math.Pow(point.Y - outputPort.Position.Y, 2));

                    if (distance <= SnapRange && distance < closestDistance)
                    {
                        closestDistance = distance;
                        closestPort = outputPort;
                    }
                }
            }

            _sourcePort = closestPort;
        }

        [RelayCommand]
        private void CancelConnect(Point point)
        {
            Port closestPort = null;
            Connection connectionToCancel = null;
            double closestDistance = double.MaxValue;
            const double SnapRange = 15.0;

            foreach (var node in Nodes)
            {
                foreach (var inputPort in node.InputPorts)
                {
                    if (inputPort.Connections.Count > 0)
                    {
                        var distance = Math.Sqrt(Math.Pow(point.X - inputPort.Position.X, 2) +
                                               Math.Pow(point.Y - inputPort.Position.Y, 2));

                        if (distance <= SnapRange && distance < closestDistance)
                        {
                            closestDistance = distance;
                            closestPort = inputPort;
                            connectionToCancel = inputPort.Connections[0];
                        }
                    }
                }
            }

            if (closestPort != null && connectionToCancel != null)
            {
                _existingConnection = connectionToCancel;

                TempLineStart = connectionToCancel.Source.Position;
                TempLineEnd = point;
                ShowTempLine = true;

                _sourcePort = connectionToCancel.Source;

                Connections.Remove(connectionToCancel);
                connectionToCancel.Source.Connections.Remove(connectionToCancel);
                connectionToCancel.Target.Connections.Remove(connectionToCancel);

                MoveConnect(point);
            }
        }

        [RelayCommand]
        private void MoveConnect(Point point)
        {
            TempLineEnd = point;

            Port closestPort = null;
            double closestDistance = double.MaxValue;
            const double SnapRange = 15.0;

            foreach (var node in Nodes)
            {
                foreach (var inputPort in node.InputPorts)
                {
                    if (_sourcePort != null &&
                        (inputPort == _sourcePort ||
                         node.OutputPorts.Contains(_sourcePort))) continue;
                    var distance = Math.Sqrt(Math.Pow(point.X - inputPort.Position.X, 2) +
                                           Math.Pow(point.Y - inputPort.Position.Y, 2));
                    if (distance <= SnapRange && distance < closestDistance)
                    {
                        closestDistance = distance;
                        closestPort = inputPort;
                    }
                }
            }

            if (closestPort != null)
            {
                TempLineEnd = closestPort.Position;
                _targetPort = closestPort;
            }
            else _targetPort = null;
        }

        [RelayCommand]
        private void EndConnect(Point point)
        {
            if (_targetPort != null && _sourcePort != null)
            {
                var connection = new Connection
                {
                    Source = _sourcePort,
                    Target = _targetPort
                };

                Connections.Add(connection);
                _sourcePort.Connections.Add(connection);
                _targetPort.Connections.Add(connection);
            }
            ShowTempLine = false;

            _sourcePort = null;
            _targetPort = null;
            _existingConnection = null;
        }

        [RelayCommand]
        private async Task SaveProjectAsync()
        {
            try
            {
                await JsonSerializer.SaveToFileAsync(Nodes, Connections);
                // 可以添加保存成功的提示
            }
            catch (Exception ex)
            {
                // 处理异常
            }
        }

        [RelayCommand]
        private async Task LoadProjectAsync()
        {
            try
            {
                var dataModel = await JsonSerializer.LoadFromFileAsync();
                if (dataModel != null)
                {
                    Nodes.Clear();
                    Connections.Clear();

                    foreach (var node in dataModel.Nodes)
                    {
                        Nodes.Add(node);
                    }

                    foreach (var connection in dataModel.Connections)
                    {
                        Connections.Add(connection);
                    }
                }
            }
            catch (Exception ex)
            {
                // 处理异常
            }
        }

        /// <summary>
        /// 生成测试节点数据
        /// </summary>
        private void GenerateTestNodes()
        {
            Nodes.Clear();

            var node1 = new ShaderNode
            {
                Title = "Color Input",
                X = 100,
                Y = 100,
                Width = 220,
                Height = 180
            };
            node1.OutputPorts.Add(new Port
            {
                Name = "Color",
                Type = typeof(Color),
                IsInput = false,
            });
            node1.Properties.Add(new Property { Name = "Red", Type = typeof(double), Value = 1.0 });
            node1.Properties.Add(new Property { Name = "Green", Type = typeof(double), Value = 0.5 });
            node1.Properties.Add(new Property { Name = "Blue", Type = typeof(double), Value = 0.0 });
            node1.Properties.Add(new Property { Name = "Alpha", Type = typeof(double), Value = 1.0 });

            var node2 = new ShaderNode
            {
                Title = "Mix Shader",
                X = 500,
                Y = 200,
                Width = 240
            };
            node2.InputPorts.Add(new Port { Name = "Color A", Type = typeof(Color), IsInput = true });
            node2.InputPorts.Add(new Port { Name = "Color B", Type = typeof(Color), IsInput = true });
            node2.InputPorts.Add(new Port { Name = "Factor", Type = typeof(float), IsInput = true });
            node2.OutputPorts.Add(new Port { Name = "Result", Type = typeof(Color), IsInput = false });
            node2.Properties.Add(new Property { Name = "Mix Factor", Type = typeof(double), Value = 0.5 });

            var node3 = new ShaderNode
            {
                Title = "Output",
                X = 900,
                Y = 150
            };
            node3.InputPorts.Add(new Port { Name = "Final Color", Type = typeof(Color), IsInput = true });
            node3.Properties.Add(new Property { Name = "Preview", Type = typeof(bool), Value = true });

            Nodes.Add(node1);
            Nodes.Add(node2);
            Nodes.Add(node3);

            var conn = new Connection
            {
                Source = node1.OutputPorts[0],
                Target = node2.InputPorts[0]
            };

            Connections.Add(conn);
            node1.OutputPorts[0].Connections.Add(conn);
            node2.InputPorts[0].Connections.Add(conn);
        }
    }
}