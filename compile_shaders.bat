@echo off
setlocal enabledelayedexpansion

set OUT=build\shaders
if not exist %OUT% mkdir %OUT%

if defined WindowsSdkDir (
    set SDK=!WindowsSdkDir!bin\
    if exist "!SDK!fxc.exe" (
        goto :found_fxc
    )
)

set SDK_PATHS=(
    "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\"
    "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22000.0\x64\"
    "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\"
    "C:\Program Files (x86)\Windows Kits\10\bin\10.0.18362.0\x64\"
    "C:\Program Files (x86)\Windows Kits\8.1\bin\x64\"
    "C:\Program Files (x86)\Windows Kits\8.0\bin\x64\"
)

for %%P in (%SDK_PATHS%) do (
    if exist "%%Pfxc.exe" (
        set SDK=%%P
        goto :found_fxc
    )
)

where fxc.exe >nul 2>&1
if !ERRORLEVEL! EQU 0 (
set SDK=
    goto :found_fxc
)

echo Error: Could not find fxc.exe (HLSL compiler)
echo Please install Windows SDK or update the SDK path in compile_shaders.bat
echo You can download Windows SDK from: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/
exit /b 1

:found_fxc
echo Using fxc.exe from: %SDK%

if "%SDK%"=="" (
    fxc.exe /T vs_5_0 /E mainVS /Fo %OUT%\TriangleVS.cso shaders\Triangle.hlsl
    fxc.exe /T ps_5_0 /E mainPS /Fo %OUT%\TrianglePS.cso shaders\Triangle.hlsl
) else (
"%SDK%fxc.exe" /T vs_5_0 /E mainVS /Fo %OUT%\TriangleVS.cso shaders\Triangle.hlsl
"%SDK%fxc.exe" /T ps_5_0 /E mainPS /Fo %OUT%\TrianglePS.cso shaders\Triangle.hlsl
)

if !ERRORLEVEL! EQU 0 (
    echo CSO generation done.
    exit /b 0
) else (
    echo CSO generation failed.
    echo Please check if shaders\Triangle.hlsl exists and contains valid HLSL code.
    exit /b 1
)