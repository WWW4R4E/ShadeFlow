using CommunityToolkit.Mvvm.ComponentModel;

namespace ShadeFlow.Models
{
  public partial class Connection : ObservableObject
  {
    [ObservableProperty]
    private Port source;

    [ObservableProperty]
    private Port target;
  }
}
