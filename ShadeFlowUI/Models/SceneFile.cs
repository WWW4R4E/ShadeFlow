using System.Collections.Generic;

namespace ShadeFlow.Models
{
    /// <summary>
    /// 场景对象的最小描述：类型 + 参数 + 位置。保存/加载场景 JSON 的基本单元，
    /// 也是论文「场景描述格式设计」一节对应的实现。
    /// </summary>
    public class SceneObjectData
    {
        /// <summary>几何类型：cube / sphere / cylinder / cone</summary>
        public string Type { get; set; } = "cube";

        /// <summary>场景树里显示的名字</summary>
        public string Name { get; set; } = "";

        // 三种几何体的参数各取所需，冗余存不用的字段比拆多态类型简单
        public double Size { get; set; } = 1.0;
        public double Radius { get; set; } = 0.5;
        public double Height { get; set; } = 1.0;
        public uint Segments { get; set; } = 32;

        /// <summary>世界坐标 [x, y, z]</summary>
        public double[] Position { get; set; } = new double[] { 0.0, 0.0, 0.0 };
    }

    /// <summary>
    /// 场景文件根对象。version 用于将来格式演进时做迁移判断。
    /// </summary>
    public class SceneFile
    {
        public int Version { get; set; } = 1;
        public List<SceneObjectData> Objects { get; set; } = new List<SceneObjectData>();
    }
}
