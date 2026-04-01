// 顶点着色器输入
struct VertexInput {
    float3 position : POSITION;
    float4 color : COLOR;
};

// 顶点着色器输出
struct VertexOutput {
    float4 position : SV_POSITION;
    float4 color : COLOR;
};

// 常量缓冲区
cbuffer ConstantBuffer {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

// 顶点着色器
VertexOutput VS(VertexInput input) {
    VertexOutput output;
    
    // 计算MVP矩阵
    float4x4 mvp = mul(projection, mul(view, model));
    
    // 转换顶点位置
    output.position = mul(mvp, float4(input.position, 1.0));
    output.color = input.color;
    
    return output;
}

// 像素着色器
float4 PS(VertexOutput input) : SV_Target {
    return input.color;
}