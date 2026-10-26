// 带纹理管线（position_texcoord 布局）的着色器，与 Basic3DTextured.vert/.frag
// 一一对应。根签名的 t0/s0 描述符表由 Shader.zig 按 TEXCOORD 语义自动生成。
cbuffer constants : register(b0)
{
    float4x4 mView;
    float4x4 mProj;
    float4x4 mWorld;
    float4 gColor;
    float4 timeAndSelect; // x: time, y: is_select (0.0 或 1.0), z,w: 填充
    float4 gLightDir; // xyz: 世界空间方向光（指向光源），w: 环境光强度
};

Texture2D colorTexture : register(t0);
SamplerState colorSampler : register(s0);

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
};

// 顶点着色器
VSOutput mainVS(float3 pos : POSITION, float3 normal : NORMAL, float2 uv : TEXCOORD)
{
    VSOutput output;
    float4 worldPos = mul(mWorld, float4(pos, 1.0f));
    float4 viewPos = mul(mView, worldPos);
    output.position = mul(mProj, viewPos);
    output.uv = uv;
    output.worldNormal = mul((float3x3)mWorld, normal);
    return output;
}

// 像素着色器
float4 mainPS(VSOutput input) : SV_Target
{
    float time = timeAndSelect.x;
    float is_select = timeAndSelect.y;

    // 漫反射：half-lambert（环境光 + 方向光），避免背光面全黑
    float3 n = normalize(input.worldNormal);
    float ndl = max(dot(n, gLightDir.xyz), 0.0f);
    float light = gLightDir.w + (1.0f - gLightDir.w) * ndl;

    // 基础颜色 = 纹理采样 * gColor * 光照
    float4 texColor = colorTexture.Sample(colorSampler, input.uv);
    float3 baseColor = texColor.rgb * gColor.rgb * light;

    // 选中高亮（与 Basic3D.hlsl 同一套）
    if (is_select > 0.5f) {
        float3 gold = float3(1.0f, 0.8f, 0.2f);
        float glow = 0.5f + 0.5f * sin(time * 3.0f);
        float3 selectedColor = lerp(baseColor, gold, 0.7f);
        selectedColor = selectedColor * (1.0f + glow * 0.5f);
        return float4(selectedColor, texColor.a * gColor.a);
    }

    return float4(baseColor, texColor.a * gColor.a);
}
