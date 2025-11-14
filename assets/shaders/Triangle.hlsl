// 定义常量缓冲区
cbuffer constants: register(b0)
{
    float4 gColor;
    float time;  // 添加时间变量
    float3 padding; // 保持16字节对齐
};

// 顶点着色器
float4 mainVS(float3 pos : POSITION) : SV_Position
{
    return float4(pos, 1.0f);
}

// 像素着色器 - 使用时间值来动态改变颜色
float4 mainPS() : SV_Target
{
    // 使用时间值创建动态颜色变化效果
    float r = sin(time) * 0.5 + 0.5;
    float g = sin(time + 2.094) * 0.5 + 0.5;  // 2.094 = 2*PI/3 (120度相位差)
    float b = sin(time + 4.188) * 0.5 + 0.5;  // 4.188 = 4*PI/3 (240度相位差)
    return float4(r, g, b, 1.0f);
}