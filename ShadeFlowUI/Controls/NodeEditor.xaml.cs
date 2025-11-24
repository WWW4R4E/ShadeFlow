using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using ShadeFlow.ViewModels;
using System.Collections;
using System.Windows.Input;
namespace ShadeFlow.Controls
{
    public sealed partial class NodeEditor : ScrollView
    {
        private NodeEditorViewModel _viewModel;

        public NodeEditor()
        {
            InitializeComponent();
            _viewModel = NodeEditorViewModel.Instance;
            _viewModel.editor = this;
        }
        public static readonly DependencyProperty ItemsSourceProperty =
            DependencyProperty.Register(
                nameof(ItemsSource),
                typeof(IEnumerable),
                typeof(NodeEditor),
                new PropertyMetadata(null, OnItemsSourceChanged));

        public IEnumerable ItemsSource
        {
            get => (IEnumerable)GetValue(ItemsSourceProperty);
            set => SetValue(ItemsSourceProperty, value);
        }
        private static void OnItemsSourceChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var control = (NodeEditor)d;
            control.UpdateItemsSource();
        }

        // TODO 添加数据绑定和更新逻辑
        private void UpdateItemsSource()
        {
        }

        /// <summary>
        /// 移动节点
        /// </summary>
        /// <param name="delta">移动的偏移量</param>
        public void MoveNode(object delta)
        {
            // 实现节点移动的逻辑
        }


        #region Commands
        public ICommand BringNodeToFrontCommand => _viewModel?.BringNodeToFrontCommand;
        
        public ICommand ConnectStartCommand => _viewModel?.StartConnectCommand;
        
        public ICommand ConnectMoveCommand => _viewModel?.MoveConnectCommand;
        
        public ICommand ConnectEndCommand => _viewModel?.EndConnectCommand;
        
        public ICommand CancelConnectCommand => _viewModel?.CancelConnectCommand;
        #endregion

    }
}