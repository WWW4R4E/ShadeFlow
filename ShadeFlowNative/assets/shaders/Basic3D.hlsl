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
float4 mainVS(float3 pos : POSITION, float4 color : COLOR) : SV_Position
{
    float4 worldPos = mul(mWorld, float4(pos, 1.0f));
    float4 viewPos = mul(mView, worldPos);
    return mul(mProj, viewPos);
}

// 像素着色器
float4 mainPS(float4 pos : SV_Position) : SV_Target
{
    return gColor;
}