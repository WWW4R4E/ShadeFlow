@echo off

REM D3D12 后端的着色器编译：fxc 的 vs_5_0/ps_5_0 二进制 D3D12 不认，
REM 必须用 dxc + SM 6.x。dxc 通常在：
REM   - Windows SDK：Windows Kits\10\bin\<version>\x64\dxc.exe
REM   - 或者 Vulkan SDK / 独立 DXC 安装
REM SDK 版本不同要改 DXC_PATH。

set OUT=zig-out\shaders
if not exist %OUT% mkdir %OUT%

echo Using dxc.exe to compile shaders (SM 6.0)

set SHADER_DIR=assets\shaders
set DXC_PATH="C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe"

REM 遍历目录下所有 .hlsl 文件
for %%f in (%SHADER_DIR%\*.hlsl) do (
    set "FILE_NAME=%%~nf"

    REM 编译顶点着色器
    echo Compiling %%~nf Vertex Shader...
    %DXC_PATH% /T vs_6_0 /E mainVS /Fo %OUT%\%%~nfVS.cso %%f
    if %ERRORLEVEL% NEQ 0 (
        echo Vertex shader compilation failed for %%~nf.
        echo Please check if shader file exists and contains valid HLSL code.
        exit /b 1
    )

    REM 编译像素着色器
    echo Compiling %%~nf Pixel Shader...
    %DXC_PATH% /T ps_6_0 /E mainPS /Fo %OUT%\%%~nfPS.cso %%f
    if %ERRORLEVEL% NEQ 0 (
        echo Pixel shader compilation failed for %%~nf.
        echo Please check if shader file exists and contains valid HLSL code.
        exit /b 1
    )
)

echo Shaders compiled successfully.
exit /b 0
