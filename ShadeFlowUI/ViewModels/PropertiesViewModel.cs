using CommunityToolkit.Mvvm.ComponentModel;

namespace ShadeFlow.ViewModels
{
    public partial class PropertiesViewModel : ObservableObject
    {
        private static readonly PropertiesViewModel _instance = new PropertiesViewModel();

        private PropertiesViewModel()
        {
        }

        public static PropertiesViewModel Instance => _instance;
    }
}