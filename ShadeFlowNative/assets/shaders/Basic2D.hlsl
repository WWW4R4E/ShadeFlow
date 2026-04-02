// 定义常量缓冲区
cbuffer constants: register(b0)
{
    float4 gColor;
    float time;
    float3 padding;
};

struct VSOutput 
{
    float4 position : SV_Position;
    float4 color : COLOR;
};

// 顶点着色器
VSOutput mainVS(float3 pos : POSITION, float4 color : COLOR)
{
    VSOutput output;
    output.position = float4(pos, 1.0f);
    output.color = color;
    return output;
}

// 像素着色器
float4 mainPS(VSOutput input) : SV_Target
{
    return input.color;
}