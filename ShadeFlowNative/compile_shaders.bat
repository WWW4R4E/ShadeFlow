@echo off

set OUT=zig-out\shaders
if not exist %OUT% mkdir %OUT%

echo Using fxc.exe to compile shaders

set SHADER_DIR=assets\shaders
set FXC_PATH="C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe"

REM 遍历目录下所有 .hlsl 文件
for %%f in (%SHADER_DIR%\*.hlsl) do (
    REM 获取文件名（不含扩展名）
    set "FILE_NAME=%%~nf"
    
    REM 编译顶点着色器
    echo Compiling %%~nf Vertex Shader...
    %FXC_PATH% /T vs_5_0 /E mainVS /Fo %OUT%\%%~nfVS.cso %%f
    if %ERRORLEVEL% NEQ 0 (
        echo Vertex shader compilation failed for %%f.
        echo Please check if shader file exists and contains valid HLSL code.
        exit /b 1
    )
    
    REM 编译像素着色器
    echo Compiling %%~nf Pixel Shader...
    %FXC_PATH% /T ps_5_0 /E mainPS /Fo %OUT%\%%~nfPS.cso %%f
    if %ERRORLEVEL% NEQ 0 (
        echo Pixel shader compilation failed for %%f.
        echo Please check if shader file exists and contains valid HLSL code.
        exit /b 1
    )
)

echo Shaders compiled successfully.
exit /b 0