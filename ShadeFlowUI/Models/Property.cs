using CommunityToolkit.Mvvm.ComponentModel;
using System;

namespace ShadeFlow.Models
{
    public partial class Property : ObservableObject
    {
        [ObservableProperty]
        private string name;

        [ObservableProperty]
        private Type type;

        [ObservableProperty]
        private object value;
    }
}