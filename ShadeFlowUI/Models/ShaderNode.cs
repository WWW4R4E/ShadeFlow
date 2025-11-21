namespace ShadeFlow.Models
{
    public class ShaderNode : NodeBase
    {
        private string _shaderType = "Fragment";

        public ShaderNode()
        {
            Title = "Shader Node";
            Description = "A basic shader node";
        }
        public string ShaderType
        {
            get => _shaderType;
            set
            {
                _shaderType = value;
                OnPropertyChanged();
            }
        }
    }
}