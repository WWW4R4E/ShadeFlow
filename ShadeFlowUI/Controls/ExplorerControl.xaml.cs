using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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
        }

        // 加载指定路径的文件夹
        public void LoadFolder(string folderPath)
        {
            _treeViewItems = new ObservableCollection<TreeViewItemModel>();

            var rootFolder = new TreeViewItemModel
            {
                Name = System.IO.Path.GetFileName(folderPath),
                IsExpanded = true
            };

            LoadFolderContents(rootFolder, folderPath);

            _treeViewItems.Add(rootFolder);
            FileTreeView.ItemsSource = _treeViewItems;
        }

        // 递归加载文件夹内容
        private void LoadFolderContents(TreeViewItemModel parent, string folderPath)
        {
            foreach (var subFolderPath in System.IO.Directory.GetDirectories(folderPath))
            {
                var folderName = System.IO.Path.GetFileName(subFolderPath);
                var folderItem = new TreeViewItemModel
                {
                    Name = folderName,
                    IsExpanded = false
                };
                parent.Children.Add(folderItem);
                LoadFolderContents(folderItem, subFolderPath);
            }

            foreach (var filePath in System.IO.Directory.GetFiles(folderPath))
            {
                var fileName = System.IO.Path.GetFileName(filePath);
                var fileItem = new TreeViewItemModel
                {
                    Name = fileName,
                    Icon = "\uE7C3"
                };
                parent.Children.Add(fileItem);
            }
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
                OnPropertyChanged(nameof(Icon));
            }
        }

        public ObservableCollection<TreeViewItemModel> Children { get; set; } = new ObservableCollection<TreeViewItemModel>();

        // 根据展开状态返回适当的文件夹图标，否则返回默认图标
        private string GetDefaultIcon()
        {
            if (_icon != null) return _icon;

            if (Children.Count > 0)
            {
                return IsExpanded ? "\uE838" : "\uE8B7";
            }

            return "\uE7C3";
        }

        public event PropertyChangedEventHandler PropertyChanged;

        private void OnPropertyChanged(string propertyName)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}