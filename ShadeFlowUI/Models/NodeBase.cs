using ShadeFlow.Controls;
using CommunityToolkit.Mvvm.ComponentModel;
using System.Collections.ObjectModel;

namespace ShadeFlow.Models
{
    public partial class NodeBase : ObservableObject
    {
        public ObservableCollection<Port> InputPorts { get; } = new ObservableCollection<Port>();
        public ObservableCollection<Port> OutputPorts { get; } = new ObservableCollection<Port>();
        public ObservableCollection<Property> Properties { get; } = new ObservableCollection<Property>();
        
        [ObservableProperty]
        private int _zIndex;
        
        [ObservableProperty]
        private string _title = "Node";
        
        [ObservableProperty]
        private string _description = "";
        
        [ObservableProperty]
        private double _x;
        
        [ObservableProperty]
        private double _y;
        
        [ObservableProperty]
        private double _width = 200;
        
        [ObservableProperty]
        private double _height = 120;
        
        [ObservableProperty]
        private bool _isSelected;
        
        public ShadeNode? Visual { get; set; }
        
        public void MoveTo(double x, double y)
        {
            X = x;
            Y = y;
        }
        
        public void MoveBy(double deltaX, double deltaY)
        {
            X += deltaX;
            Y += deltaY;
        }
    }
}