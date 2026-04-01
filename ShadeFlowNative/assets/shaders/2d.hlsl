// 2D渲染着色器

// 纹理采样器
Texture2D g_texture : register(t0);
SamplerState g_sampler : register(s0);

// 顶点着色器输入 (CanvasRenderer)
struct VertexInput {
    float2 position : POSITION;
    float4 color : COLOR;
};

// 顶点着色器输出
struct VertexOutput {
    float4 position : SV_POSITION;
    float4 color : COLOR;
};

// 顶点着色器 (CanvasRenderer)
VertexOutput mainVS(VertexInput input) {
    VertexOutput output;
    
    // 直接传递位置和颜色
    output.position = float4(input.position, 0.0, 1.0);
    output.color = input.color;
    
    return output;
}

// 像素着色器 (CanvasRenderer)
float4 mainPS(VertexOutput input) : SV_Target {
    return input.color;
}

// 顶点着色器输入 (SpriteRenderer)
struct SpriteVertexInput {
    float2 position : POSITION;
    float2 uv : TEXCOORD0;
};

// 顶点着色器输出 (SpriteRenderer)
struct SpriteVertexOutput {
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;
};

// 顶点着色器 (SpriteRenderer)
SpriteVertexOutput SpriteVS(SpriteVertexInput input) {
    SpriteVertexOutput output;
    
    // 直接传递位置和UV
    output.position = float4(input.position, 0.0, 1.0);
    output.uv = input.uv;
    
    return output;
}

// 像素着色器 (SpriteRenderer)
float4 SpritePS(SpriteVertexOutput input) : SV_Target {
    // 采样纹理
    return tex2D(g_sampler, input.uv);
}