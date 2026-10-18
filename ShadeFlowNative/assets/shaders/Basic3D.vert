#version 450

// 与 Basic3D.hlsl 的 mainVS 一一对应（Linux/Vulkan 路径用）。
//
// 矩阵约定：std140 的 mat4 是列主序，与 fxc 按列打包 float4x4 的方式读同一串
// 字节，所以这里直接 `mProj * (mView * (mWorld * v))` 就等价于 HLSL 的
// `mul(mProj, mul(mView, mul(mWorld, v)))`，不需要转置。
//
// Y 轴由后端用负高度 viewport 翻转（见 Pipeline.zig），投影矩阵不用改。
layout(std140, set = 0, binding = 0) uniform Constants {
    mat4 mView;
    mat4 mProj;
    mat4 mWorld;
    vec4 gColor;
    vec4 timeAndSelect; // x: time, y: is_select, z,w: 填充
};

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;

layout(location = 0) out vec4 vertexColor;

void main() {
    vec4 worldPos = mWorld * vec4(inPosition, 1.0);
    vec4 viewPos = mView * worldPos;
    gl_Position = mProj * viewPos;
    vertexColor = inColor;
}
