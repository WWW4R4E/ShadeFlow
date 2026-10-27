using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using ShadeFlow.Models;
using System.Linq;
using System;
using System.Collections.Generic;
using System.Numerics;

namespace ShadeFlow.Views.Controls
{
    public sealed partial class PropertiesControl : UserControl
    {
        private NodeBase _currentNode;

        // 当前在属性面板里编辑的场景对象（null = 未选中）
        private TreeViewItemModel _currentSceneObject;

        // 参数编辑框（键 = 参数名），Apply 时统一读取
        private readonly Dictionary<string, TextBox> _paramBoxes = new Dictionary<string, TextBox>();

        public PropertiesControl()
        {
            this.InitializeComponent();

            // 场景树选中（含视口拾取联动）→ 显示对象属性
            SceneTreeControl.SceneObjectSelected += OnSceneObjectSelected;
            this.Unloaded += (s, e) => SceneTreeControl.SceneObjectSelected -= OnSceneObjectSelected;
        }

        // ------------------------------------------------------------------
        // 对象属性（场景对象）
        // ------------------------------------------------------------------

        private void OnSceneObjectSelected(object sender, TreeViewItemModel item)
        {
            ShowSceneObject(item);
        }

        private void ShowSceneObject(TreeViewItemModel item)
        {
            _currentSceneObject = item;
            _paramBoxes.Clear();
            ParamsPanel.Children.Clear();

            if (item?.SceneData == null)
            {
                // 分组节点 / 未选中：隐藏对象属性区，回到空态提示
                ObjectPanel.Visibility = Visibility.Collapsed;
                NoSelectionText.Text = "在场景树或 3D 视口中选择一个对象";
                NoSelectionText.Visibility = Visibility.Visible;
                return;
            }

            var data = item.SceneData;
            NoSelectionText.Visibility = Visibility.Collapsed;
            ObjectPanel.Visibility = Visibility.Visible;

            ObjectNameBox.Text = item.Name;
            ObjectTypeText.Text = data.Type;

            PosXBox.Text = data.Position[0].ToString("0.###");
            PosYBox.Text = data.Position[1].ToString("0.###");
            PosZBox.Text = data.Position[2].ToString("0.###");

            AddParamBox(data.Type == "cube" ? "size" : "radius", data.Type == "cube" ? data.Size : data.Radius);
            if (data.Type == "cylinder" || data.Type == "cone")
            {
                AddParamBox("height", data.Height);
            }
            if (data.Type != "cube")
            {
                AddParamBox("segments", data.Segments);
            }
        }

        private void AddParamBox(string name, double value)
        {
            var label = new TextBlock
            {
                Text = name,
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 2)
            };
            var box = new TextBox
            {
                Text = value.ToString("0.###"),
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 8)
            };
            ParamsPanel.Children.Add(label);
            ParamsPanel.Children.Add(box);
            _paramBoxes[name] = box;
        }

        // 应用：把面板里的值写回 SceneData；参数/位置变化走「单删 + 原位重建」
        private void ApplyObjectButton_Click(object sender, RoutedEventArgs e)
        {
            if (_currentSceneObject?.SceneData == null || SceneTreeControl.Instance == null) return;

            var old = _currentSceneObject.SceneData;
            var data = new SceneObjectData
            {
                Type = old.Type,
                Name = string.IsNullOrWhiteSpace(ObjectNameBox.Text) ? old.Name : ObjectNameBox.Text,
                Size = old.Size,
                Radius = old.Radius,
                Height = old.Height,
                Segments = old.Segments,
                Position = old.Position
            };

            if (TryReadFloat(PosXBox, v => data.Position[0] = v) &&
                TryReadFloat(PosYBox, v => data.Position[1] = v) &&
                TryReadFloat(PosZBox, v => data.Position[2] = v) &&
                TryReadParams(data))
            {
                if (SceneTreeControl.Instance.UpdateObjectParams(_currentSceneObject, data))
                {
                    // 名字可能被改：同步树节点显示
                    _currentSceneObject.Name = data.Name;
                    ShowSceneObject(_currentSceneObject);
                }
                else
                {
                    ShowApplyError("应用失败：引擎重建对象出错，详见 Debug 输出。");
                }
            }
            else
            {
                ShowApplyError("参数格式不正确，请输入有效数字。");
            }
        }

        private bool TryReadFloat(TextBox box, Action<double> assign)
        {
            if (double.TryParse(box.Text, out double value))
            {
                assign(value);
                return true;
            }
            return false;
        }

        private bool TryReadParams(SceneObjectData data)
        {
            foreach (var pair in _paramBoxes)
            {
                if (!double.TryParse(pair.Value.Text, out double value)) return false;
                switch (pair.Key)
                {
                    case "size": data.Size = value; break;
                    case "radius": data.Radius = value; break;
                    case "height": data.Height = value; break;
                    case "segments": data.Segments = System.Convert.ToUInt32(Math.Max(3, Math.Round(value))); break;
                }
            }
            return true;
        }

        private async void ShowApplyError(string message)
        {
            var dialog = new ContentDialog
            {
                Title = "对象属性",
                Content = message,
                CloseButtonText = "确定",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }

        // ------------------------------------------------------------------
        // 着色器节点属性（节点编辑器）
        // ------------------------------------------------------------------

        public void UpdateProperties(NodeBase node)
        {
            _currentNode = node;

            if (node != null)
            {
                SelectedShaderName.Text = node.Title;
                NoSelectionText.Visibility = Visibility.Collapsed;
                PropertyEditorPanel.Visibility = Visibility.Visible;

                // 清空现有内容
                ConstantsPanel.Children.Clear();
                InputsPanel.Children.Clear();
                OutputsPanel.Children.Clear();

                // 添加常量编辑器（来自Properties集合）
                foreach (var property in node.Properties)
                {
                    AddConstantEditor(property);
                }

                // 添加输入编辑器
                foreach (var input in node.InputPorts)
                {
                    AddInputEditor(input);
                }

                // 添加输出编辑器
                foreach (var output in node.OutputPorts)
                {
                    AddOutputEditor(output);
                }
            }
            else
            {
                SelectedShaderName.Text = "(No Selection)";
                NoSelectionText.Visibility = Visibility.Collapsed;
                PropertyEditorPanel.Visibility = Visibility.Visible;
                
                // 清空内容
                ConstantsPanel.Children.Clear();
                InputsPanel.Children.Clear();
                OutputsPanel.Children.Clear();
                
                // 显示无选择消息
                NoSelectionText.Visibility = Visibility.Visible;
                PropertyEditorPanel.Visibility = Visibility.Collapsed;
            }
        }

        private void AddConstantEditor(Property property)
        {
            var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
            
            var label = new TextBlock
            {
                Text = property.Name,
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 4)
            };

            FrameworkElement editor;
            // 使用Type的FullName属性进行比较，同时兼容基本类型别名
            Type propType = property.Type;
            if (propType == typeof(float) || propType == typeof(double))
            {
                var floatBox = new TextBox
                {
                    Text = property.Value?.ToString(),
                    FontSize = 12,
                    PlaceholderText = "Enter float value"
                };
                floatBox.LostFocus += (sender, e) =>
                {
                    if (float.TryParse(((TextBox)sender).Text, out float result))
                    {
                        property.Value = result;
                    }
                };
                editor = floatBox;
            }
            else if (propType == typeof(int) || propType == typeof(short) || propType == typeof(long))
            {
                var intBox = new TextBox
                {
                    Text = property.Value?.ToString(),
                    FontSize = 12,
                    PlaceholderText = "Enter integer value"
                };
                intBox.LostFocus += (sender, e) =>
                {
                    if (int.TryParse(((TextBox)sender).Text, out int result))
                    {
                        property.Value = result;
                    }
                };
                editor = intBox;
            }
            else if (propType == typeof(bool))
            {
                var boolToggle = new ToggleSwitch
                {
                    IsOn = Convert.ToBoolean(property.Value),
                    FontSize = 12
                };
                boolToggle.Toggled += (sender, e) =>
                {
                    property.Value = ((ToggleSwitch)sender).IsOn;
                };
                editor = boolToggle;
            }
            else if (propType == typeof(Vector2))
            {
                // 使用Grid来创建平均分布的列
                var gridPanel = new Grid();
                int componentCount = 2;
                
                // 添加指定数量的列，每列宽度相等
                for (int i = 0; i < componentCount; i++)
                {
                    gridPanel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                }
                
                var components = property.Value?.ToString()?.Split(',');
                
                for (int i = 0; i < componentCount; i++)
                {
                    var compBox = new TextBox
                    {
                        Text = components != null && i < components.Length ? components[i].Trim() : "0",
                        FontSize = 12,
                        Margin = new Thickness(2, 0, 2, 0)
                    };
                    
                    // 设置列位置
                    compBox.SetValue(Grid.ColumnProperty, i);
                    
                    compBox.LostFocus += (sender, e) =>
                    {
                        UpdateVectorValue(property);
                    };
                    
                    gridPanel.Children.Add(compBox);
                }
                
                editor = gridPanel;
            }
            else if (propType == typeof(Vector3))
            {
                // 使用Grid来创建平均分布的列
                var gridPanel = new Grid();
                int componentCount = 3;
                
                // 添加指定数量的列，每列宽度相等
                for (int i = 0; i < componentCount; i++)
                {
                    gridPanel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                }
                
                var components = property.Value?.ToString()?.Split(',');
                
                for (int i = 0; i < componentCount; i++)
                {
                    var compBox = new TextBox
                    {
                        Text = components != null && i < components.Length ? components[i].Trim() : "0",
                        FontSize = 12,
                        Margin = new Thickness(2, 0, 2, 0)
                    };
                    
                    // 设置列位置
                    compBox.SetValue(Grid.ColumnProperty, i);
                    
                    compBox.LostFocus += (sender, e) =>
                    {
                        UpdateVectorValue(property);
                    };
                    
                    gridPanel.Children.Add(compBox);
                }
                
                editor = gridPanel;
            }
            else if (propType == typeof(Vector4))
            {
                // 使用Grid来创建平均分布的列
                var gridPanel = new Grid();
                int componentCount = 4;
                
                // 添加指定数量的列，每列宽度相等
                for (int i = 0; i < componentCount; i++)
                {
                    gridPanel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                }
                
                var components = property.Value?.ToString()?.Split(',');
                
                for (int i = 0; i < componentCount; i++)
                {
                    var compBox = new TextBox
                    {
                        Text = components != null && i < components.Length ? components[i].Trim() : "0",
                        FontSize = 12,
                        Margin = new Thickness(2, 0, 2, 0)
                    };
                    
                    // 设置列位置
                    compBox.SetValue(Grid.ColumnProperty, i);
                    
                    compBox.LostFocus += (sender, e) =>
                    {
                        UpdateVectorValue(property);
                    };
                    
                    gridPanel.Children.Add(compBox);
                }
                
                editor = gridPanel;
            }
            else
            {
                var textBox = new TextBox
                {
                    Text = property.Value?.ToString(),
                    FontSize = 12,
                    PlaceholderText = "Enter value"
                };
                textBox.LostFocus += (sender, e) =>
                {
                    property.Value = ((TextBox)sender).Text;
                };
                editor = textBox;
            }

            panel.Children.Add(label);
            panel.Children.Add(editor);
            ConstantsPanel.Children.Add(panel);
        }

        private void AddInputEditor(Port input)
        {
            var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 8) };
            
            var label = new TextBlock
            {
                Text = $"{input.Name} ({input.Type?.Name})",
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 4)
            };
            
            var status = new TextBlock
            {
                Text = input.Connections.Count > 0 ? "Connected" : "Not Connected",
                FontSize = 11,
                Opacity = 0.7,
                Margin = new Thickness(0, 0, 0, 4)
            };
            
            panel.Children.Add(label);
            panel.Children.Add(status);
            InputsPanel.Children.Add(panel);
        }

        private void AddOutputEditor(Port output)
        {
            var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 8) };
            
            var label = new TextBlock
            {
                Text = $"{output.Name} ({output.Type?.Name})",
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 4)
            };
            
            var status = new TextBlock
            {
                Text = output.Connections.Count > 0 ? $"Connected to {output.Connections.Count} node(s)" : "Not Connected",
                FontSize = 11,
                Opacity = 0.7,
                Margin = new Thickness(0, 0, 0, 4)
            };
            
            panel.Children.Add(label);
            panel.Children.Add(status);
            OutputsPanel.Children.Add(panel);
        }

        private void UpdateVectorValue(Property property)
        {
            // 查找包含此属性的面板
            foreach (var child in ConstantsPanel.Children)
            {
                var stackPanel = child as StackPanel;
                if (stackPanel != null && stackPanel.Children.Count > 0)
                {
                    var textBlock = stackPanel.Children[0] as TextBlock;
                    if (textBlock != null && textBlock.Text == property.Name)
                    {
                        // 找到对应的面板，获取输入框的值
                        if (stackPanel.Children.Count > 1)
                        {
                            // 检查是Grid还是StackPanel
                            if (stackPanel.Children[1] is Grid grid)
                            {
                                var textBoxValues = grid.Children
                                    .OfType<TextBox>()
                                    .Select(tb => tb.Text)
                                    .ToArray();
                                
                                property.Value = string.Join(", ", textBoxValues);
                            }
                            // 兼容原有的StackPanel布局
                            else if (stackPanel.Children[1] is StackPanel textBoxesPanel)
                            {
                                var textBoxValues = textBoxesPanel.Children
                                    .OfType<TextBox>()
                                    .Select(tb => tb.Text)
                                    .ToArray();
                                
                                property.Value = string.Join(", ", textBoxValues);
                            }
                        }
                        break;
                    }
                }
            }
        }
    }
}