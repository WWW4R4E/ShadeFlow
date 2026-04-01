// 定义常量缓冲区
cbuffer constants: register(b0)
{
    float4x4 mView;
    float4x4 mProj;
    float4x4 mWorld;
    float4 gColor;
    float time;
    float3 padding;
};

// 顶点着色器
float4 mainVS(float3 pos : POSITION) : SV_Position
{
    float4 worldPos = mul(mWorld, float4(pos, 1.0f));
    float4 viewPos = mul(mView, worldPos);
    return mul(mProj, viewPos);
}

// 像素着色器
float4 mainPS(float4 pos : SV_Position) : SV_Target
{
    // 使用时间值创建动态颜色变化效果
    float r = sin(time) * 0.5 + 0.5;
    float g = sin(time + 2.094) * 0.5 + 0.5;  // 2.094 = 2*PI/3 (120度相位差)
    float b = sin(time + 4.188) * 0.5 + 0.5;  // 4.188 = 4*PI/3 (240度相位差)
    return float4(r, g, b, 1.0f);
}