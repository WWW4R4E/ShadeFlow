#version 450

// 带纹理管线（position_texcoord 布局）的像素着色器，与 Basic3DTextured.hlsl
// 一一对应。set1 是纹理的 combined image sampler（Renderer 创建纹理时写好，
// 绘制时绑定；不贴图的对象绑默认白纹理，采样等于原色）。
//
// uniform 块约定见 Basic3D.frag。
layout(std140, set = 0, binding = 0) uniform Constants {
    mat4 mView;
    mat4 mProj;
    mat4 mWorld;
    vec4 gColor;
    vec4 timeAndSelect; // x: time, y: is_select, z,w: 填充
};

layout(set = 1, binding = 0) uniform sampler2D colorTexture;

layout(location = 0) in vec2 vertexUV;
layout(location = 0) out vec4 outColor;

void main() {
    float time = timeAndSelect.x;
    float is_select = timeAndSelect.y;

    // 基础颜色 = 纹理采样 × gColor。
    vec4 texColor = texture(colorTexture, vertexUV);
    vec3 baseColor = texColor.rgb * gColor.rgb;

    // 选中时换成金色并加脉动发光（与 Basic3D.frag 同一套）。
    if (is_select > 0.5) {
        vec3 gold = vec3(1.0, 0.8, 0.2);
        float glow = 0.5 + 0.5 * sin(time * 3.0);
        vec3 selectedColor = mix(baseColor, gold, 0.7);
        selectedColor = selectedColor * (1.0 + glow * 0.5);
        outColor = vec4(selectedColor, texColor.a * gColor.a);
        return;
    }

    outColor = vec4(baseColor, texColor.a * gColor.a);
}
