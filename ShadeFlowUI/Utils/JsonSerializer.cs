using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Windows.Storage;
using Windows.Storage.Pickers;
using ShadeFlow.Models;
using System.Collections.ObjectModel;

namespace ShadeFlow.Utils
{
    /// <summary>
    /// JSON序列化工具类，用于保存和读取节点数据
    /// </summary>
    public static class JsonSerializer
    {
        /// <summary>
        /// 序列化设置
        /// </summary>
        private static readonly JsonSerializerOptions _options = new JsonSerializerOptions
        {
            WriteIndented = true,
            ReferenceHandler = ReferenceHandler.Preserve,
            Converters = { new TypeConverter() }
        };

        /// <summary>
        /// 保存节点数据到文件
        /// </summary>
        /// <param name="nodes">节点集合</param>
        /// <param name="connections">连接集合</param>
        public static async Task SaveToFileAsync(ObservableCollection<NodeBase> nodes, ObservableCollection<Connection> connections)
        {
            // 创建保存数据模型
            var dataModel = new NodeEditorDataModel
            {
                Nodes = nodes,
                Connections = connections
            };

            // 打开文件保存对话框
            FileSavePicker savePicker = new FileSavePicker();
            savePicker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
            savePicker.FileTypeChoices.Add("JSON 文件", new[] { ".json" });
            savePicker.SuggestedFileName = "ShadeFlowProject.json";

            // 获取文件对象
            StorageFile file = await savePicker.PickSaveFileAsync();
            if (file != null)
            {
                // 序列化并保存
                var jsonString = System.Text.Json.JsonSerializer.Serialize(dataModel, _options);
                await FileIO.WriteTextAsync(file, jsonString);
            }
        }

        /// <summary>
        /// 从文件读取节点数据
        /// </summary>
        /// <returns>节点数据模型</returns>
        public static async Task<NodeEditorDataModel> LoadFromFileAsync()
        {
            // 打开文件选择对话框
            FileOpenPicker openPicker = new FileOpenPicker();
            openPicker.ViewMode = PickerViewMode.Thumbnail;
            openPicker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
            openPicker.FileTypeFilter.Add(".json");

            // 获取文件对象
            StorageFile file = await openPicker.PickSingleFileAsync();
            if (file != null)
            {
                // 读取并反序列化
                var jsonString = await FileIO.ReadTextAsync(file);
                return System.Text.Json.JsonSerializer.Deserialize<NodeEditorDataModel>(jsonString, _options);
            }

            return null;
        }

        /// <summary>
        /// 类型转换器，处理Type类型的序列化
        /// </summary>
        private class TypeConverter : JsonConverter<Type>
        {
            public override Type Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
            {
                var typeName = reader.GetString();
                if (string.IsNullOrEmpty(typeName))
                    return null;

                return Type.GetType(typeName);
            }

            public override void Write(Utf8JsonWriter writer, Type value, JsonSerializerOptions options)
            {
                if (value == null)
                {
                    writer.WriteNullValue();
                    return;
                }

                writer.WriteStringValue(value.AssemblyQualifiedName);
            }
        }
    }

    /// <summary>
    /// 节点编辑器数据模型
    /// </summary>
    public class NodeEditorDataModel
    {
        /// <summary>
        /// 节点集合
        /// </summary>
        public ObservableCollection<NodeBase> Nodes { get; set; }

        /// <summary>
        /// 连接集合
        /// </summary>
        public ObservableCollection<Connection> Connections { get; set; }
    }
}