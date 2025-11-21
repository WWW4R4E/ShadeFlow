# ShadeFlow - 现代图形应用开发框架

## 项目概述

ShadeFlow 是一个结合 Zig 原生图形引擎和 WinUI 3 现代界面的图形应用开发框架。项目采用模块化架构，支持实时着色器编辑和可视化节点编程。

## 项目结构

```
ShadeFlow/
├── ShadeFlowNative/          # Zig 原生引擎
│   ├── src/
│   │   ├── engine/
│   │   │   ├── core/         # 核心引擎 (Engine.zig)
│   │   │   ├── optional/     # 可选功能 (Window.zig, Input.zig)
│   │   │   ├── renderer/     # 渲染器模块
│   │   │   └── resources/    # 资源管理
│   │   ├── utils/            # 工具类 (Time.zig)
│   │   ├── main.zig          # 独立运行入口
│   │   └── root.zig          # C# 互操作接口
│   └── build.zig             # Zig 构建配置
├── ShadeFlowUI/              # WinUI 3 界面项目
│   ├── Views/                # 界面视图
│   ├── Controls/             # 自定义控件
│   ├── Models/               # 数据模型
│   └── Natives/              # 原生互操作
└── compile_shaders.bat       # 着色器编译脚本
```

## 核心特性

### 🎯 双模式渲染引擎
- **Composition 模式**: 专为 WinUI 3 集成设计，支持现代 UI 框架
- **HWND 模式**: 传统窗口模式，用于独立测试和调试

### 🎨 实时着色器编辑
- 支持 HLSL 着色器实时编译和预览
- 可视化节点编辑器，所见即所得
- 动态着色器加载，无需重启应用

### 🔧 模块化架构
- 清晰的职责分离：引擎核心、渲染器、资源管理
- 可选的窗口和输入系统，便于集成
- 统一的 C# 互操作接口

## 快速开始

### 环境要求
- Zig 编译器 (0.15.2)
- Windows 10/11 SDK

### 构建 Zig 引擎
```bash
cd ShadeFlowNative
zig build dll    # 构建 DLL 用于 WinUI 3 集成
zig build run    # 独立运行测试
```

### 运行独立测试
```bash
zig build run
```
