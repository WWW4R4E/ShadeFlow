// 定义常量缓冲区
cbuffer constants: register(b0)
{
    float4x4 mView;
    float4x4 mProj;
    float4x4 mWorld;
    float4 gColor;
    float4 timeAndSelect; // x: time, y: is_select (0.0 或 1.0), z,w: 填充
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
    float4 worldPos = mul(mWorld, float4(pos, 1.0f));
    float4 viewPos = mul(mView, worldPos);
    output.position = mul(mProj, viewPos);
    output.color = color;
    return output;
}

// 像素着色器
float4 mainPS(VSOutput input) : SV_Target
{
    // 提取时间和选择状态
    float time = timeAndSelect.x;
    float is_select = timeAndSelect.y;

    // 基础颜色 = 顶点颜色 * gColor（gColor作为整体颜色调整）
    float3 baseColor = input.color.rgb * gColor.rgb;

    // 高亮效果：如果被选中，使用金色并添加脉动发光
    if (is_select > 0.5f) {
        // 金色
        float3 gold = float3(1.0f, 0.8f, 0.2f);

        // 脉动发光效果
        float glow = 0.5f + 0.5f * sin(time * 3.0f);

        // 混合金色和基础颜色
        float3 selectedColor = lerp(baseColor, gold, 0.7f); // 70%金色，30%基础颜色

        // 添加脉动发光
        selectedColor = selectedColor * (1.0f + glow * 0.5f);

        return float4(selectedColor, input.color.a * gColor.a);
    }

    return float4(baseColor, input.color.a * gColor.a);
}
