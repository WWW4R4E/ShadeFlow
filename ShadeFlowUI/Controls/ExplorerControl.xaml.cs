using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Data;
using System.Collections.ObjectModel;
using System.ComponentModel;

namespace ShadeFlow.Controls
{
    public sealed partial class ExplorerControl : UserControl
    {
        private ObservableCollection<TreeViewItemModel> _treeViewItems;

        public ExplorerControl()
        {
            this.InitializeComponent();
            LoadSampleData();
        }

        private void LoadSampleData()
        {
            _treeViewItems = new ObservableCollection<TreeViewItemModel>();

            // 创建示例根目录
            var rootFolder = new TreeViewItemModel
            {
                Name = "ShadeFlow Project",
                IsExpanded = true
            };

            // 添加子项
            rootFolder.Children.Add(new TreeViewItemModel { Name = "Assets", IsExpanded = false });
            rootFolder.Children.Add(new TreeViewItemModel { Name = "Models", IsExpanded = false });
            rootFolder.Children.Add(new TreeViewItemModel { Name = "Views", IsExpanded = false });
            rootFolder.Children.Add(new TreeViewItemModel { Name = "ViewModels", IsExpanded = false });
            rootFolder.Children.Add(new TreeViewItemModel { Name = "Controls", IsExpanded = false });
            rootFolder.Children.Add(new TreeViewItemModel { Name = "Utils", IsExpanded = false });

            var shadersFolder = new TreeViewItemModel
            {
                Name = "Shaders",
                IsExpanded = true
            };
            shadersFolder.Children.Add(new TreeViewItemModel { Name = "vertex.hlsl", Icon = "\uE7C3" }); // File icon
            shadersFolder.Children.Add(new TreeViewItemModel { Name = "pixel.hlsl", Icon = "\uE7C3" });
            shadersFolder.Children.Add(new TreeViewItemModel { Name = "compute.hlsl", Icon = "\uE7C3" });
            rootFolder.Children.Add(shadersFolder);

            rootFolder.Children.Add(new TreeViewItemModel { Name = "App.xaml", Icon = "\uE7C3" });
            rootFolder.Children.Add(new TreeViewItemModel { Name = "MainWindow.xaml", Icon = "\uE7C3" });
            rootFolder.Children.Add(new TreeViewItemModel { Name = "ShadeFlow.sln", Icon = "\uE7C3" }); // Solution icon

            _treeViewItems.Add(rootFolder);
            FileTreeView.ItemsSource = _treeViewItems;
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
    }

    // 数据模型
    public class TreeViewItemModel : INotifyPropertyChanged
    {
        private string _name;
        private bool _isExpanded;
        private string _icon;

        public string Name 
        { 
            get => _name; 
            set 
            { 
                _name = value; 
                OnPropertyChanged(nameof(Name)); 
            } 
        }
        
        public string Icon 
        { 
            get => _icon ?? GetDefaultIcon(); 
            set 
            { 
                _icon = value; 
                OnPropertyChanged(nameof(Icon)); 
            } 
        }
        
        public bool IsExpanded 
        { 
            get => _isExpanded; 
            set 
            { 
                _isExpanded = value; 
                OnPropertyChanged(nameof(IsExpanded)); 
                OnPropertyChanged(nameof(Icon)); // 当展开状态改变时触发图标更新
            } 
        }

        public ObservableCollection<TreeViewItemModel> Children { get; set; } = new ObservableCollection<TreeViewItemModel>();

        // 根据展开状态返回适当的文件夹图标，否则返回默认图标
        private string GetDefaultIcon()
        {
            if (_icon != null) return _icon; // 如果已设置特定图标，则直接返回
            
            if (Children.Count > 0) // 是一个文件夹
            {
                return IsExpanded ? "\uE838" : "\uE8B7"; // 展开时用 \uE838，闭合时用 \uE8B7
            }
            
            return "\uE7C3"; // 新的文件图标
        }

        public event PropertyChangedEventHandler PropertyChanged;

        private void OnPropertyChanged(string propertyName)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}