#version 450

// 与 Basic3D.hlsl 的 mainPS 一一对应（Linux/Vulkan 路径用）。
//
// uniform 块必须把三个矩阵也声明出来，且顺序、类型与顶点着色器完全一致：
// 成员偏移由 std140 决定，只写用到的成员会让 gColor/timeAndSelect 落到偏移
// 0/16，读到的其实是矩阵的数据。
layout(std140, set = 0, binding = 0) uniform Constants {
    mat4 mView;
    mat4 mProj;
    mat4 mWorld;
    vec4 gColor;
    vec4 timeAndSelect; // x: time, y: is_select, z,w: 填充
    vec4 gLightDir; // xyz: 世界空间方向光（指向光源），w: 环境光强度
};

layout(location = 0) in vec4 vertexColor;
layout(location = 1) in vec3 worldNormal;
layout(location = 0) out vec4 outColor;

void main() {
    float time = timeAndSelect.x;
    float is_select = timeAndSelect.y;

    // 漫反射：half-lambert（环境光 + 方向光），避免背光面全黑
    vec3 n = normalize(worldNormal);
    float ndl = max(dot(n, gLightDir.xyz), 0.0);
    float light = gLightDir.w + (1.0 - gLightDir.w) * ndl;

    // 基础颜色 = 顶点颜色 * gColor * 光照
    vec3 baseColor = vertexColor.rgb * gColor.rgb * light;

    // 选中时换成金色并加脉动发光
    if (is_select > 0.5) {
        vec3 gold = vec3(1.0, 0.8, 0.2);
        float glow = 0.5 + 0.5 * sin(time * 3.0);
        vec3 selectedColor = mix(baseColor, gold, 0.7); // 70% 金色，30% 基础颜色
        selectedColor = selectedColor * (1.0 + glow * 0.5);
        outColor = vec4(selectedColor, vertexColor.a * gColor.a);
        return;
    }

    outColor = vec4(baseColor, vertexColor.a * gColor.a);
}
