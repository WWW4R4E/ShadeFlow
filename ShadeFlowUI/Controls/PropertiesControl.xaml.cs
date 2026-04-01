using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using ShadeFlow.Models;
using System.Linq;
using System;
using System.Diagnostics;
using System.Numerics;

namespace ShadeFlow.Controls
{
    public sealed partial class PropertiesControl : UserControl
    {
        private NodeBase _currentNode;

        public PropertiesControl()
        {
            this.InitializeComponent();
            // TODO 完成选取绑定后删除例子数据
            LoadSampleNode();
        }

        private void LoadSampleNode()
        {
            // 创建一个示例节点作为默认显示
            var sampleNode = new NodeBase
            {
                Title = "Sample Shader Node",
                Description = "A sample shader node for demonstration"
            };

            // 添加一些示例属性
            sampleNode.Properties.Add(new Property { Name = "Time", Type = typeof(float), Value = 1.5f });
            sampleNode.Properties.Add(new Property { Name = "Scale", Type = typeof(float), Value = 2.0f });
            sampleNode.Properties.Add(new Property { Name = "Enabled", Type = typeof(bool), Value = true });
            sampleNode.Properties.Add(new Property { Name = "Resolution", Type = typeof(Vector2), Value = "800, 600" });

            // 添加示例输入端口 - 使用已知类型或通用object类型
            sampleNode.InputPorts.Add(new Port { Name = "Texture Input", Type = typeof(object), IsInput = true });
            sampleNode.InputPorts.Add(new Port { Name = "Normal Map", Type = typeof(object), IsInput = true });

            // 添加示例输出端口
            sampleNode.OutputPorts.Add(new Port { Name = "Color Output", Type = typeof(Vector4), IsInput = false });
            sampleNode.OutputPorts.Add(new Port { Name = "Depth Output", Type = typeof(float), IsInput = false });

            UpdateProperties(sampleNode);
        }

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