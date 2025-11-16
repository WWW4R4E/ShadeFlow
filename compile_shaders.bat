@echo off

set OUT=zig-out\shaders
if not exist %OUT% mkdir %OUT%

echo Using fxc.exe to compile shaders
echo Compiling Triangle Vertex Shader...
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe" /T vs_5_0 /E mainVS /Fo %OUT%\TriangleVS.cso assets\shaders\Triangle.hlsl
if %ERRORLEVEL% NEQ 0 (
    echo Vertex shader compilation failed.
    echo Please check if shader files exist and contain valid HLSL code.
    exit /b 1
)

echo Compiling Triangle Pixel Shader...
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe" /T ps_5_0 /E mainPS /Fo %OUT%\TrianglePS.cso assets\shaders\Triangle.hlsl
if %ERRORLEVEL% NEQ 0 (
    echo Pixel shader compilation failed.
    echo Please check if shader files exist and contain valid HLSL code.
    exit /b 1
)

echo Compiling Cube Vertex Shader...
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe" /T vs_5_0 /E mainVS /Fo %OUT%\CubeVS.cso assets\shaders\Cube.hlsl
if %ERRORLEVEL% NEQ 0 (
    echo Vertex shader compilation failed.
    echo Please check if shader files exist and contain valid HLSL code.
    exit /b 1
)

echo Compiling Cube Pixel Shader...
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe" /T ps_5_0 /E mainPS /Fo %OUT%\CubePS.cso assets\shaders\Cube.hlsl
if %ERRORLEVEL% NEQ 0 (
    echo Pixel shader compilation failed.
    echo Please check if shader files exist and contain valid HLSL code.
    exit /b 1
)

echo Shaders compiled successfully.
exit /b 0