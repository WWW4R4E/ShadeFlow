using System.Collections.ObjectModel;
using System.ComponentModel;

namespace ShadeFlow.Models
{
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

        public event PropertyChangedEventHandler? PropertyChanged;

        private void OnPropertyChanged(string propertyName)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}