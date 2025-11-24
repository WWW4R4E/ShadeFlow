using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using ShadeFlow.Models;

namespace ShadeFlow.Views.Tools
{
    public class PropertyTemplateSelector : DataTemplateSelector
    {
        public DataTemplate StringTemplate { get; set; }
        public DataTemplate NumberTemplate { get; set; }
        public DataTemplate BoolTemplate { get; set; }

        protected override DataTemplate SelectTemplateCore(object item, DependencyObject container)
        {
            if (item is Property property)
            {
                if (property.Type == typeof(bool))
                    return BoolTemplate;
                else if (property.Type == typeof(double) || property.Type == typeof(int) || property.Type == typeof(float))
                    return NumberTemplate;
                else
                    return StringTemplate;
            }

            return base.SelectTemplateCore(item, container);
        }
    }
}