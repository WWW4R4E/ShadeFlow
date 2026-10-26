#version 450

// 带纹理管线（position_texcoord 布局）的顶点着色器，与 Basic3DTextured.hlsl
// 一一对应。矩阵/std140 约定见 Basic3D.vert。
//
// set1（combined image sampler）在像素阶段采样，这里只透传 UV。
layout(std140, set = 0, binding = 0) uniform Constants {
    mat4 mView;
    mat4 mProj;
    mat4 mWorld;
    vec4 gColor;
    vec4 timeAndSelect; // x: time, y: is_select, z,w: 填充
};

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUV;

layout(location = 0) out vec2 vertexUV;

void main() {
    vec4 worldPos = mWorld * vec4(inPosition, 1.0);
    vec4 viewPos = mView * worldPos;
    gl_Position = mProj * viewPos;
    vertexUV = inUV;
}
