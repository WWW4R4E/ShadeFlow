using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace ShadeFlow.Models
{
    public class NodeBase : INotifyPropertyChanged
    {
        private string _title = "Node";
        private string _description = "";
        private double _x;
        private double _y;
        private double _width = 200;
        private double _height = 120;
        private bool _isSelected;

        public string Title
        {
            get => _title;
            set
            {
                _title = value;
                OnPropertyChanged();
            }
        }

        public string Description
        {
            get => _description;
            set
            {
                _description = value;
                OnPropertyChanged();
            }
        }

        public double X
        {
            get => _x;
            set
            {
                _x = value;
                OnPropertyChanged();
            }
        }

        public double Y
        {
            get => _y;
            set
            {
                _y = value;
                OnPropertyChanged();
            }
        }

        public double Width
        {
            get => _width;
            set
            {
                _width = value;
                OnPropertyChanged();
            }
        }

        public double Height
        {
            get => _height;
            set
            {
                _height = value;
                OnPropertyChanged();
            }
        }

        public bool IsSelected
        {
            get => _isSelected;
            set
            {
                _isSelected = value;
                OnPropertyChanged();
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }


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