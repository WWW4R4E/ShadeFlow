// 常量缓冲区
cbuffer ConstantBuffer{
    float4x4 g_WorldViewProjection;
};

// 顶点着色器
struct VSInput{
    float3 position:POSITION;
    float4 color:COLOR;
};

// 顶点着色器输出
struct VSOutput{
    float4 position: SV_POSITION;
    float4 color: COLOR;
};

// 顶点着色器
VSOutput VS(VSInput input){
    VSOutput output;
    output.position = mul(g_WorldViewProjection, float4(input.position, 1.0f));
    output.color = input.color;
    return output;
}

// 像素着色器输入
struct PSInput{
    float4 position: SV_POSITION;
    float4 color: COLOR;
};

// 像素着色器
float PS(PSInput input):SV_Target{
    return input.color;
};
