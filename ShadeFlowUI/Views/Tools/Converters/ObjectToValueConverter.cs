using Microsoft.UI.Xaml.Data;
using System;

namespace ShadeFlow.Views.Tools.Converters
{
    public class ObjectToValueConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, string language)
        {
            return value;
        }

        public object ConvertBack(object value, Type targetType, object parameter, string language)
        {
            return value;
        }
    }
}