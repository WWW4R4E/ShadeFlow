using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ShadeFlow.Models;
using System.Collections.ObjectModel;

namespace ShadeFlow.ViewModels
{
    public partial class HomePageViewModel : ObservableObject
    {
        #region ObservableProperty
        // 渲染状态
        [ObservableProperty]
        private bool _isRendering = false;

        // 渲染错误信息
        [ObservableProperty]
        private string _errorMessage = string.Empty;
        #endregion

        public HomePageViewModel()
        {
            var renderViewModel = RenderPreViewModel.Instance;
            
            IsRendering = renderViewModel.IsRendering;
            ErrorMessage = renderViewModel.ErrorMessage;
        }

        public RenderPreViewModel RenderViewModel => RenderPreViewModel.Instance;
        public NodeEditorViewModel NodeEditorViewModel => NodeEditorViewModel.Instance;
        public PropertiesViewModel PropertiesViewModel => PropertiesViewModel.Instance;
        
        public ObservableCollection<NodeBase> Nodes => NodeEditorViewModel.Instance.Nodes;

        public IRelayCommand ResizeRendererCommand => RenderPreViewModel.Instance.ResizeRendererCommand;
        public IRelayCommand CleanupCommand => RenderPreViewModel.Instance.CleanupCommand;
        public IRelayCommand InitializeRendererCommand => RenderPreViewModel.Instance.InitializeRendererCommand;
    }
}