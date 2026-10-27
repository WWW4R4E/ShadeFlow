using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using ShadeFlow.Models;
using ShadeFlow.Natives;
using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace ShadeFlow.Views.Controls
{
    public sealed partial class SceneTreeControl : UserControl
    {
        /// <summary>
        /// 全局唯一实例：MainWindow 的文件菜单（保存/加载场景）通过它进入场景树。
        /// </summary>
        public static SceneTreeControl? Instance { get; private set; }

        /// <summary>
        /// 场景树选中变化时触发（视口拾取联动也会走到这里）；参数为选中的节点，
        /// 取消选中时为 null。属性面板订阅它显示对象属性。
        /// </summary>
        public static event EventHandler<TreeViewItemModel> SceneObjectSelected;

        private ObservableCollection<TreeViewItemModel> _treeViewItems;

        public SceneTreeControl()
        {
            this.InitializeComponent();
            Instance = this;
            LoadTestData();

            // 3D 视口里左键拾取 → 场景树联动选中（Unloaded 退订防泄漏）。
            SwapChainControl.ObjectPicked += OnViewportObjectPicked;
            this.Unloaded += (s, e) => SwapChainControl.ObjectPicked -= OnViewportObjectPicked;

            // 树选中 → 属性面板（含取消选中）
            SceneTreeView.SelectionChanged += (s, e) =>
            {
                SceneObjectSelected?.Invoke(this, SceneTreeView.SelectedItem as TreeViewItemModel);
            };
        }

        // 视口拾取联动：按引擎索引找到树节点并选中（点空处引擎已清空选中，树不动）。
        private void OnViewportObjectPicked(object sender, int engineIndex)
        {
            if (engineIndex < 0) return;
            var item = FindByEngineIndex(engineIndex);
            if (item != null)
            {
                SceneTreeView.SelectedItem = item;
            }
        }

        // 按引擎索引递归找树节点
        private TreeViewItemModel FindByEngineIndex(int engineIndex)
        {
            var itemsSource = SceneTreeView.ItemsSource as IEnumerable<TreeViewItemModel>;
            if (itemsSource == null) return null;
            foreach (var rootItem in itemsSource)
            {
                var found = FindByEngineIndexRecursive(rootItem, engineIndex);
                if (found != null) return found;
            }
            return null;
        }

        private TreeViewItemModel FindByEngineIndexRecursive(TreeViewItemModel current, int engineIndex)
        {
            if (current.EngineIndex == engineIndex) return current;
            foreach (var child in current.Children)
            {
                var found = FindByEngineIndexRecursive(child, engineIndex);
                if (found != null) return found;
            }
            return null;
        }

        // 加载测试数据
        private void LoadTestData()
        {
            _treeViewItems = new ObservableCollection<TreeViewItemModel>();

            var sceneRoot = new TreeViewItemModel
            {
                Name = "Scene",
                IsExpanded = true,
                Icon = "\uE86F"
            };

            // 添加相机
            var camera = new TreeViewItemModel
            {
                Name = "Main Camera",
                Icon = "\uE724"
            };
            sceneRoot.Children.Add(camera);

            //// 添加光照
            //var light = new TreeViewItemModel
            //{
            //    Name = "Directional Light",
            //    Icon = "\uE706"
            //};
            //sceneRoot.Children.Add(light);

            // 添加几何体
            var geometry = new TreeViewItemModel
            {
                Name = "Geometry",
                IsExpanded = true,
                Icon = "\uE7B8"
            };

            sceneRoot.Children.Add(geometry);

            // 添加材质
            var materials = new TreeViewItemModel
            {
                Name = "Materials",
                IsExpanded = true,
                Icon = "\uE7C4"
            };

            var material1 = new TreeViewItemModel
            {
                Name = "Default Material",
                Icon = "\uE7C4"
            };
            materials.Children.Add(material1);

            sceneRoot.Children.Add(materials);

            _treeViewItems.Add(sceneRoot);
            SceneTreeView.ItemsSource = _treeViewItems;
        }

        // 处理折叠所有按钮点击事件
        private void CollapseAllButton_Click(object sender, RoutedEventArgs e)
        {
            CollapseAllItems(_treeViewItems);
        }

        private void CollapseAllItems(ObservableCollection<TreeViewItemModel> items)
        {
            foreach (var item in items)
            {
                item.IsExpanded = false;
                if (item.Children.Count > 0)
                {
                    CollapseAllItems(item.Children);
                }
            }
        }

        // 处理右键点击事件
        private void SceneTreeView_RightTapped(object sender, Microsoft.UI.Xaml.Input.RightTappedRoutedEventArgs e)
        {
            var clickedItem = e.OriginalSource as FrameworkElement;
            if (clickedItem?.DataContext is TreeViewItemModel model)
            {
                SceneTreeView.SelectedItem = model;
            }
        }

        // 找到指定项目的父节点
        private TreeViewItemModel FindParentOfItem(ObservableCollection<TreeViewItemModel> collection, TreeViewItemModel item)
        {
            foreach (var model in collection)
            {
                if (model.Children.Contains(item))
                {
                    return model;
                }
                
                // 递归搜索子节点
                var foundInChild = FindParentOfItem(model.Children, item);
                if (foundInChild != null)
                {
                    return foundInChild;
                }
            }
            
            return null;
        }

        // 添加节点菜单项点击事件
        private void AddNodeMenuItem_Click(object sender, RoutedEventArgs e)
        {
            if (SceneTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                var newNode = new TreeViewItemModel
                {
                    Name = "New Node",
                    Icon = "\uE7B8", // 默认图标
                };
                selectedItem.Children.Add(newNode);
            }
        }

        // 删除节点菜单项点击事件
        private void DeleteNodeMenuItem_Click(object sender, RoutedEventArgs e)
        {
            if (SceneTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                // 引擎对象：先单删引擎侧（删除后后续索引前移），分组节点只动树
                if (selectedItem.EngineIndex >= 0)
                {
                    if (ShadeFlowNative.RemoveRenderObject(selectedItem.EngineIndex))
                    {
                        ShiftEngineIndexes(selectedItem.EngineIndex);
                    }
                }
                RemoveItemFromTree(selectedItem);
            }
        }
        
        // 从树中移除项目
        private void RemoveItemFromTree(TreeViewItemModel itemToRemove)
        {
            // 从根开始查找并移除项目
            foreach (var rootItem in SceneTreeView.ItemsSource as IEnumerable<TreeViewItemModel>)
            {
                if (RemoveItemRecursive(rootItem, itemToRemove))
                    return;
            }
        }

        // 递归查找并移除项目
        private bool RemoveItemRecursive(TreeViewItemModel parent, TreeViewItemModel itemToRemove)
        {
            // 检查直接子项
            if (parent.Children.Contains(itemToRemove))
            {
                parent.Children.Remove(itemToRemove);
                return true;
            }

            // 递归检查子项的子项
            foreach (var child in parent.Children)
            {
                if (RemoveItemRecursive(child, itemToRemove))
                    return true;
            }

            return false;
        }

        // 重命名节点菜单项点击事件
        private async void RenameNodeMenuItem_Click(object sender, RoutedEventArgs e)
        {
            if (SceneTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                var renameLayout = new StackPanel();
                var textBox = new TextBox()
                {
                    Text = selectedItem.Name,
                    Margin = new Thickness(0, 10, 0, 10)
                };

                renameLayout.Children.Add(textBox);

                ContentDialog renameDialog = new ContentDialog()
                {
                    Title = "重命名节点",
                    Content = renameLayout,
                    PrimaryButtonText = "确定",
                    CloseButtonText = "取消",
                    XamlRoot = this.XamlRoot
                };

                var result = await renameDialog.ShowAsync();
                if (result == ContentDialogResult.Primary)
                {
                    selectedItem.Name = textBox.Text;
                }
            }
        }

        // 为TreeViewItem的键盘加速器添加事件处理方法
        private void TreeViewItem_DeleteAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            DeleteNodeMenuItem_Click(null, null);
            args.Handled = true;
        }

        private void TreeViewItem_RenameAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            RenameNodeMenuItem_Click(null, null);
            args.Handled = true;
        }

        private void TreeViewItem_DuplicateAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            DuplicateNodeMenuItem_Click(null, null);
            args.Handled = true;
        }

        // 复制节点菜单项点击事件
        private void DuplicateNodeMenuItem_Click(object sender, RoutedEventArgs e)
        {
            if (SceneTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                var duplicatedItem = new TreeViewItemModel
                {
                    Name = selectedItem.Name + " (副本)",
                    Icon = selectedItem.Icon,
                    IsExpanded = selectedItem.IsExpanded
                };

                // 复制子节点
                foreach (var child in selectedItem.Children)
                {
                    duplicatedItem.Children.Add(new TreeViewItemModel
                    {
                        Name = child.Name,
                        Icon = child.Icon,
                        IsExpanded = child.IsExpanded
                    });
                }

                // 找到 selected Item 的父节点并添加复制的节点
                var parent = FindParentOfItem(selectedItem);
                if (parent != null)
                {
                    parent.Children.Add(duplicatedItem);
                }
                else
                {
                    // 如果没有找到父节点，说明是根节点，无法复制
                    ContentDialog dialog = new ContentDialog()
                    {
                        Title = "复制节点",
                        Content = "无法复制根节点",
                        CloseButtonText = "确定",
                        XamlRoot = this.XamlRoot
                    };
                    _ = dialog.ShowAsync();
                }
            }
        }

        // 查找指定项的父项
        private TreeViewItemModel FindParentOfItem(TreeViewItemModel item)
        {
            var itemsSource = SceneTreeView.ItemsSource as IEnumerable<TreeViewItemModel>;
            if (itemsSource != null)
            {
                foreach (var rootItem in itemsSource)
                {
                    var parent = FindParentRecursive(rootItem, item);
                    if (parent != null)
                        return parent;
                }
            }
            return null;
        }

        // 递归查找父项
        private TreeViewItemModel FindParentRecursive(TreeViewItemModel current, TreeViewItemModel target)
        {
            foreach (var child in current.Children)
            {
                if (child == target)
                    return current;

                var result = FindParentRecursive(child, target);
                if (result != null)
                    return result;
            }
            return null;
        }

        // 添加立方体菜单项点击事件
        private async void AddCubeMenuItem_Click(object sender, RoutedEventArgs e)
        {
            // 显示立方体参数输入对话框
            var dialog = new ContentDialog
            {
                Title = "添加立方体",
                Content = new StackPanel
                {
                    Children = {
                        new TextBlock { Text = "大小:" },
                        new TextBox { Name = "SizeTextBox", Text = "1.0" },
                        new TextBlock { Text = "X坐标:" },
                        new TextBox { Name = "PosXTextBox", Text = "0" },
                        new TextBlock { Text = "Y坐标:" },
                        new TextBox { Name = "PosYTextBox", Text = "0" },
                        new TextBlock { Text = "Z坐标:" },
                        new TextBox { Name = "PosZTextBox", Text = "0" }
                    }
                },
                PrimaryButtonText = "确定",
                CloseButtonText = "取消",
                XamlRoot = this.XamlRoot
            };

            bool isValidInput = false;
            float size = 0;
            float posX = 0;
            float posY = 0;
            float posZ = 0;

            while (!isValidInput)
            {
                var result = await dialog.ShowAsync();
                if (result != ContentDialogResult.Primary)
                {
                    return; // 用户取消
                }

                try
                {
                    size = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[1]).Text);
                    posX = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[3]).Text);
                    posY = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[5]).Text);
                    posZ = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[7]).Text);
                    isValidInput = true;
                }
                catch (FormatException)
                {
                    // 显示错误提示
                    var errorDialog = new ContentDialog
                    {
                        Title = "输入错误",
                        Content = "请输入有效的数字",
                        PrimaryButtonText = "确定",
                        XamlRoot = this.XamlRoot
                    };
                    await errorDialog.ShowAsync();
                    // 继续循环，让用户重新输入
                }
            }

            AddGeometryToEngine("Cube", ShadeFlowNative.GeometryParams.Cube(size), posX, posY, posZ);
        }

        // 添加球体菜单项点击事件
        private async void AddSphereMenuItem_Click(object sender, RoutedEventArgs e)
        {
            // 显示球体参数输入对话框
            var dialog = new ContentDialog
            {
                Title = "添加球体",
                Content = new StackPanel
                {
                    Children = {
                        new TextBlock { Text = "半径:" },
                        new TextBox { Name = "RadiusTextBox", Text = "0.5" },
                        new TextBlock { Text = "分段数:" },
                        new TextBox { Name = "SegmentsTextBox", Text = "32" },
                        new TextBlock { Text = "X坐标:" },
                        new TextBox { Name = "PosXTextBox", Text = "0" },
                        new TextBlock { Text = "Y坐标:" },
                        new TextBox { Name = "PosYTextBox", Text = "0" },
                        new TextBlock { Text = "Z坐标:" },
                        new TextBox { Name = "PosZTextBox", Text = "0" }
                    }
                },
                PrimaryButtonText = "确定",
                CloseButtonText = "取消",
                XamlRoot = this.XamlRoot
            };

            bool isValidInput = false;
            float radius = 0;
            uint segments = 0;
            float posX = 0;
            float posY = 0;
            float posZ = 0;

            while (!isValidInput)
            {
                var result = await dialog.ShowAsync();
                if (result != ContentDialogResult.Primary)
                {
                    return; // 用户取消
                }

                try
                {
                    radius = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[1]).Text);
                    segments = uint.Parse(((TextBox)((StackPanel)dialog.Content).Children[3]).Text);
                    posX = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[5]).Text);
                    posY = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[7]).Text);
                    posZ = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[9]).Text);
                    isValidInput = true;
                }
                catch (FormatException)
                {
                    // 显示错误提示
                    var errorDialog = new ContentDialog
                    {
                        Title = "输入错误",
                        Content = "请输入有效的数字",
                        PrimaryButtonText = "确定",
                        XamlRoot = this.XamlRoot
                    };
                    await errorDialog.ShowAsync();
                    // 继续循环，让用户重新输入
                }
            }

            AddGeometryToEngine("Sphere", ShadeFlowNative.GeometryParams.Sphere(radius, segments), posX, posY, posZ);
        }

        // 添加圆柱体菜单项点击事件
        private async void AddCylinderMenuItem_Click(object sender, RoutedEventArgs e)
        {
            // 显示圆柱体参数输入对话框
            var dialog = new ContentDialog
            {
                Title = "添加圆柱体",
                Content = new StackPanel
                {
                    Children = {
                        new TextBlock { Text = "半径:" },
                        new TextBox { Name = "RadiusTextBox", Text = "0.5" },
                        new TextBlock { Text = "高度:" },
                        new TextBox { Name = "HeightTextBox", Text = "1.0" },
                        new TextBlock { Text = "分段数:" },
                        new TextBox { Name = "SegmentsTextBox", Text = "32" },
                        new TextBlock { Text = "X坐标:" },
                        new TextBox { Name = "PosXTextBox", Text = "0" },
                        new TextBlock { Text = "Y坐标:" },
                        new TextBox { Name = "PosYTextBox", Text = "0" },
                        new TextBlock { Text = "Z坐标:" },
                        new TextBox { Name = "PosZTextBox", Text = "0" }
                    }
                },
                PrimaryButtonText = "确定",
                CloseButtonText = "取消",
                XamlRoot = this.XamlRoot
            };

            bool isValidInput = false;
            float radius = 0;
            float height = 0;
            uint segments = 0;
            float posX = 0;
            float posY = 0;
            float posZ = 0;

            while (!isValidInput)
            {
                var result = await dialog.ShowAsync();
                if (result != ContentDialogResult.Primary)
                {
                    return; // 用户取消
                }

                try
                {
                    radius = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[1]).Text);
                    height = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[3]).Text);
                    segments = uint.Parse(((TextBox)((StackPanel)dialog.Content).Children[5]).Text);
                    posX = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[7]).Text);
                    posY = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[9]).Text);
                    posZ = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[11]).Text);
                    isValidInput = true;
                }
                catch (FormatException)
                {
                    // 显示错误提示
                    var errorDialog = new ContentDialog
                    {
                        Title = "输入错误",
                        Content = "请输入有效的数字",
                        PrimaryButtonText = "确定",
                        XamlRoot = this.XamlRoot
                    };
                    await errorDialog.ShowAsync();
                    // 继续循环，让用户重新输入
                }
            }

            AddGeometryToEngine("Cylinder", ShadeFlowNative.GeometryParams.Cylinder(radius, height, segments), posX, posY, posZ);
        }

        // 添加圆锥体菜单项点击事件
        private async void AddConeMenuItem_Click(object sender, RoutedEventArgs e)
        {
            // 显示圆锥体参数输入对话框
            var dialog = new ContentDialog
            {
                Title = "添加圆锥体",
                Content = new StackPanel
                {
                    Children = {
                        new TextBlock { Text = "半径:" },
                        new TextBox { Name = "RadiusTextBox", Text = "0.5" },
                        new TextBlock { Text = "高度:" },
                        new TextBox { Name = "HeightTextBox", Text = "1.0" },
                        new TextBlock { Text = "分段数:" },
                        new TextBox { Name = "SegmentsTextBox", Text = "32" },
                        new TextBlock { Text = "X坐标:" },
                        new TextBox { Name = "PosXTextBox", Text = "0" },
                        new TextBlock { Text = "Y坐标:" },
                        new TextBox { Name = "PosYTextBox", Text = "0" },
                        new TextBlock { Text = "Z坐标:" },
                        new TextBox { Name = "PosZTextBox", Text = "0" }
                    }
                },
                PrimaryButtonText = "确定",
                CloseButtonText = "取消",
                XamlRoot = this.XamlRoot
            };

            bool isValidInput = false;
            float radius = 0;
            float height = 0;
            uint segments = 0;
            float posX = 0;
            float posY = 0;
            float posZ = 0;

            while (!isValidInput)
            {
                var result = await dialog.ShowAsync();
                if (result != ContentDialogResult.Primary)
                {
                    return; // 用户取消
                }

                try
                {
                    radius = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[1]).Text);
                    height = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[3]).Text);
                    segments = uint.Parse(((TextBox)((StackPanel)dialog.Content).Children[5]).Text);
                    posX = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[7]).Text);
                    posY = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[9]).Text);
                    posZ = float.Parse(((TextBox)((StackPanel)dialog.Content).Children[11]).Text);
                    isValidInput = true;
                }
                catch (FormatException)
                {
                    // 显示错误提示
                    var errorDialog = new ContentDialog
                    {
                        Title = "输入错误",
                        Content = "请输入有效的数字",
                        PrimaryButtonText = "确定",
                        XamlRoot = this.XamlRoot
                    };
                    await errorDialog.ShowAsync();
                    // 继续循环，让用户重新输入
                }
            }

            AddGeometryToEngine("Cone", ShadeFlowNative.GeometryParams.Cone(radius, height, segments), posX, posY, posZ);
        }

        // 添加几何体项到树中（返回新节点，供调用方登记引擎索引）
        private TreeViewItemModel AddGeometryItem(string name, string icon)
        {
            // 找到Geometry节点
            TreeViewItemModel geometryNode = null;
            var itemsSource = SceneTreeView.ItemsSource as IEnumerable<TreeViewItemModel>;
            if (itemsSource != null)
            {
                foreach (var rootItem in itemsSource)
                {
                    geometryNode = FindGeometryNode(rootItem);
                    if (geometryNode != null)
                        break;
                }
            }

            if (geometryNode != null)
            {
                var newGeometry = new TreeViewItemModel
                {
                    Name = name,
                    Icon = icon
                };
                geometryNode.Children.Add(newGeometry);
                return newGeometry;
            }
            return null;
        }

        // 添加几何体：统一入口——把参数折算成 SceneObjectData 登记到树节点，
        // 再调引擎（着色器路径传 null 用引擎默认）。引擎侧失败时把树节点撤掉，
        // 保证树里的索引和引擎对象一一对应。
        private void AddGeometryToEngine(string name, ShadeFlowNative.GeometryParams p, float posX, float posY, float posZ)
        {
            AddObjectFromData(DataFromParams(name, p, posX, posY, posZ));
        }

        // 按 SceneObjectData 添加对象（加载场景和交互添加共用这一条路径）
        private void AddObjectFromData(SceneObjectData data)
        {
            int engineIndex = CountEngineItems();
            var item = AddGeometryItem(string.IsNullOrEmpty(data.Name) ? data.Type : data.Name, "\uE7B8");
            if (item == null) return;

            var p = ParamsFromData(data);
            if (ShadeFlowNative.ShadeFlow_AddGeometryObjectWithParams(ref p, (float)data.Position[0], (float)data.Position[1], (float)data.Position[2], null, null))
            {
                item.EngineIndex = engineIndex;
                item.SceneData = data;
            }
            else
            {
                RemoveItemFromTree(item);
                Debug.WriteLine("添加几何体到引擎失败，已撤销树节点");
            }
        }

        // GeometryParams → SceneObjectData（保存场景用）
        private static SceneObjectData DataFromParams(string name, ShadeFlowNative.GeometryParams p, float x, float y, float z)
        {
            var data = new SceneObjectData { Name = name, Position = new double[] { x, y, z } };
            switch (p.type)
            {
                case ShadeFlowNative.GeometryType.Cube:
                    data.Type = "cube"; data.Size = p.cube.size; break;
                case ShadeFlowNative.GeometryType.Sphere:
                    data.Type = "sphere"; data.Radius = p.sphere.radius; data.Segments = p.sphere.segments; break;
                case ShadeFlowNative.GeometryType.Cylinder:
                    data.Type = "cylinder"; data.Radius = p.cylinder.radius; data.Height = p.cylinder.height; data.Segments = p.cylinder.segments; break;
                case ShadeFlowNative.GeometryType.Cone:
                    data.Type = "cone"; data.Radius = p.cone.radius; data.Height = p.cone.height; data.Segments = p.cone.segments; break;
            }
            return data;
        }

        // SceneObjectData → GeometryParams（加载场景用）
        private static ShadeFlowNative.GeometryParams ParamsFromData(SceneObjectData data)
        {
            switch (data.Type)
            {
                case "sphere": return ShadeFlowNative.GeometryParams.Sphere((float)data.Radius, data.Segments);
                case "cylinder": return ShadeFlowNative.GeometryParams.Cylinder((float)data.Radius, (float)data.Height, data.Segments);
                case "cone": return ShadeFlowNative.GeometryParams.Cone((float)data.Radius, (float)data.Height, data.Segments);
                default: return ShadeFlowNative.GeometryParams.Cube((float)data.Size);
            }
        }

        // 找到 Geometry 分组节点（找不到返回 null）
        private TreeViewItemModel FindGeometryRoot()
        {
            var itemsSource = SceneTreeView.ItemsSource as IEnumerable<TreeViewItemModel>;
            if (itemsSource == null) return null;
            foreach (var rootItem in itemsSource)
            {
                var node = FindGeometryNode(rootItem);
                if (node != null) return node;
            }
            return null;
        }

        // 保存场景：把 Geometry 下所有带参数的对象写进 JSON
        public bool SaveScene(string path)
        {
            try
            {
                var file = new SceneFile();
                var geometryNode = FindGeometryRoot();
                if (geometryNode != null)
                {
                    foreach (var child in geometryNode.Children)
                    {
                        if (child.SceneData != null)
                        {
                            file.Objects.Add(child.SceneData);
                        }
                    }
                }

                var options = new System.Text.Json.JsonSerializerOptions { WriteIndented = true };
                File.WriteAllText(path, System.Text.Json.JsonSerializer.Serialize(file, options));
                Debug.WriteLine($"场景已保存: {path}（{file.Objects.Count} 个对象）");
                return true;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"保存场景失败: {ex.Message}");
                return false;
            }
        }

        // 加载场景：清空引擎与树里的几何体（分组节点保留），按 JSON 重建
        public bool LoadScene(string path)
        {
            try
            {
                var file = System.Text.Json.JsonSerializer.Deserialize<SceneFile>(File.ReadAllText(path));
                if (file?.Objects == null)
                {
                    Debug.WriteLine("场景文件格式不正确");
                    return false;
                }

                ShadeFlowNative.ShadeFlow_ClearRenderObjects();
                var geometryNode = FindGeometryRoot();
                geometryNode?.Children.Clear();

                foreach (var data in file.Objects)
                {
                    AddObjectFromData(data);
                }
                Debug.WriteLine($"场景已加载: {path}（{file.Objects.Count} 个对象）");
                return true;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"加载场景失败: {ex.Message}");
                return false;
            }
        }

        // 统计树里已登记的引擎对象数（= 引擎当前对象数，即新对象的索引）
        private int CountEngineItems()
        {
            int count = 0;
            var itemsSource = SceneTreeView.ItemsSource as IEnumerable<TreeViewItemModel>;
            if (itemsSource == null) return 0;
            foreach (var rootItem in itemsSource)
            {
                CountEngineItemsRecursive(rootItem, ref count);
            }
            return count;
        }

        private void CountEngineItemsRecursive(TreeViewItemModel current, ref int count)
        {
            if (current.EngineIndex >= 0) count++;
            foreach (var child in current.Children)
            {
                CountEngineItemsRecursive(child, ref count);
            }
        }

        // 删除对象后，比它大的索引全部前移（引擎侧 orderedRemove 的语义）
        private void ShiftEngineIndexes(int removedIndex)
        {
            var itemsSource = SceneTreeView.ItemsSource as IEnumerable<TreeViewItemModel>;
            if (itemsSource == null) return;
            foreach (var rootItem in itemsSource)
            {
                ShiftEngineIndexesRecursive(rootItem, removedIndex);
            }
        }

        private void ShiftEngineIndexesRecursive(TreeViewItemModel current, int removedIndex)
        {
            if (current.EngineIndex > removedIndex) current.EngineIndex--;
            foreach (var child in current.Children)
            {
                ShiftEngineIndexesRecursive(child, removedIndex);
            }
        }

        // 更新对象参数/位置：引擎没有「改参数」的入口，走单删 + 追加重建。
        // 位置不变时结果视觉上无感；索引簿记保持与其他对象一一对应。
        // 失败返回 false（树节点保留，调用方提示）。
        public bool UpdateObjectParams(TreeViewItemModel item, SceneObjectData newData)
        {
            if (item.EngineIndex < 0) return false;

            int oldIndex = item.EngineIndex;
            if (!ShadeFlowNative.RemoveRenderObject(oldIndex))
            {
                Debug.WriteLine($"重建对象失败：引擎删除索引 {oldIndex} 未命中");
                return false;
            }
            ShiftEngineIndexes(oldIndex);

            int newIndex = CountEngineItems();
            var p = ParamsFromData(newData);
            if (ShadeFlowNative.ShadeFlow_AddGeometryObjectWithParams(
                    ref p,
                    (float)newData.Position[0], (float)newData.Position[1], (float)newData.Position[2],
                    null, null))
            {
                item.EngineIndex = newIndex;
                item.SceneData = newData;
                return true;
            }

            Debug.WriteLine("重建对象失败：引擎添加未成功，树节点已失去引擎对象");
            item.EngineIndex = -1;
            return false;
        }

        // 查找Geometry节点
        private TreeViewItemModel FindGeometryNode(TreeViewItemModel current)
        {
            if (current.Name == "Geometry")
                return current;

            foreach (var child in current.Children)
            {
                var result = FindGeometryNode(child);
                if (result != null)
                    return result;
            }
            return null;
        }

    }
}