@echo off

set OUT=zig-out\shaders
if not exist %OUT% mkdir %OUT%

echo Using fxc.exe to compile shaders
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe" /T vs_5_0 /E main /Fo %OUT%\TriangleVS.cso assets\shaders\basic_vertex.hlsl
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe" /T ps_5_0 /E main /Fo %OUT%\TrianglePS.cso assets\shaders\basic_pixel.hlsl

if %ERRORLEVEL% EQU 0 (
    echo CSO generation done.
    exit /b 0
) else (
    echo CSO generation failed.
    echo Please check if shader files exist and contain valid HLSL code.
    exit /b 1
)