using CommunityToolkit.Mvvm.ComponentModel;
using System;
using System.Collections.ObjectModel;
using Windows.Foundation;

namespace ShadeFlow.Models
{
  public partial class Port : ObservableObject
  {
    [ObservableProperty]
    private string name;

    [ObservableProperty]
    private Type type; 

    [ObservableProperty]
    private bool isInput;

    [ObservableProperty]
    private Point position;
    
    public ObservableCollection<Connection> Connections { get; } = new ObservableCollection<Connection>();
  }
}