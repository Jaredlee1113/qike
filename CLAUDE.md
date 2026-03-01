# CLAUDE.md

此文件为 Claude Code (claude.ai/code) 处理此项目代码时提供指导。

## 项目概述

"起的课"是一个中国传统金钱卦识别 iOS 应用，使用 Swift + SwiftUI 构建。用户通过手动输入六爻阴阳，快速得到卦象结果。

**当前版本**: 手动输入版（相机识别功能已移除）

## 技术栈

- **平台**: iOS (Swift + SwiftUI)
- **最低部署**: iOS 16.0+
- **开发环境**: Xcode 14+
- **数据存储**: 本地 JSON 文件（通过 DataStorageManager）
- **架构**: 单一 target，无第三方依赖

## 项目结构

```
TianjiApp/
├── App/
│   ├── TianjiApp.swift           # App 入口，使用 @main
│   └── ContentView.swift           # 主界面，包含开始起课、历史记录入口
├── Data/
│   ├── Models/
│   │   ├── Hexagram.swift         # 64卦数据模型和查找逻辑
│   │   ├── CoinResult.swift       # 单个爻位结果（YinYang, CoinSide）
│   │   └── DivinationSession.swift # 起课记录模型
│   └── Storage/
│       └── DataStorageManager.swift # 本地数据存储管理器
├── Views/
│   ├── CameraView.swift           # 起课界面（手动输入六爻）
│   ├── HistoryView.swift          # 历史记录列表
│   ├── ResultView.swift           # 卦象结果显示
│   └── HexagramTestView.swift     # DEBUG模式下的测试工具
├── Resources/
│   ├── HexagramData.json          # 64卦完整数据（卦名、爻辞、图解、解释）
│   ├── HexagramImages/            # 64卦卦象图片资源
│   └── Assets.xcassets            # 应用资源
└── TianjiApp.xcodeproj/           # Xcode 项目文件
```

## 核心概念

### 爻位顺序
- **六爻**: 从下到上依次为第1爻（初爻）到第6爻（上爻）
- **数组表示**: `yaos[0]` = 初爻，`yaos[5]` = 上爻
- **阴阳属性**:
  - `Yang` (阳) = 图案面，显示为实线 ─────
  - `Yin` (阴) = 字面，显示为断线 ─  ─

### 卦象查找逻辑
```swift
// 在 HexagramProvider 中实现
// 将 6 个 YinYang 数组转换为对应的卦象
HexagramProvider.findHexagram(by: yaos)
```

### 数据存储
- 使用本地 JSON 文件存储历史记录
- 不使用 SwiftData/CoreData（保持简单）
- 存储位置: 应用沙盒 Documents 目录

## 开发命令

```bash
# 模拟器构建
xcodebuild -project TianjiApp.xcodeproj -scheme TianjiApp -sdk iphonesimulator build

# 真机构建
xcodebuild -project TianjiApp.xcodeproj -scheme TianjiApp -sdk iphoneos build

# 运行测试
xcodebuild test -project TianjiApp.xcodeproj -scheme TianjiApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

## UI 规范

### 视图层级
```
ContentView (主界面)
├── 开始起课 → CameraView
├── 历史记录 → HistoryView
└── [DEBUG] 卦象测试 → HexagramTestView

CameraView (手动输入六爻)
└── 查看结果 → ResultView
```

### 设计规范
- **主色调**: 蓝色 (`Color.blue`)
- **字体**: 系统默认，标题使用 `.largeTitle.bold()`
- **圆角**: 卡片 14-24pt
- **间距**: VStack/HStack spacing 12-20pt
- **无表情符号**: 除非用户明确要求

## 开发注意事项

### 1. 爻位方向
- 显示顺序：从上到下 = 上爻 → 初爻
- 数组索引：`yaos[5]` → `yaos[0]`
- UI 中使用 `ForEach((0..<6).reversed())` 来正确显示

### 2. 阴阳符号绘制
```swift
struct YaoSymbol: View {
    // 阳: 单一实线
    // 阴: 两条断线（中间有间距）
}
```

### 3. DEBUG 工具
- `HexagramTestView` 仅在 DEBUG 模式下显示
- 使用 `#if DEBUG` 条件编译

### 4. 中文内容
- 所有 UI 文本使用简体中文
- 卦象数据来自 `HexagramData.json`
- 尊重传统易经文化术语

## 已移除功能（历史记录）

以下功能已从项目中移除，请勿尝试重新实现：
- ~~相机实时预览~~
- ~~铜钱模板匹配~~
- ~~Vision Framework 图像识别~~
- ~~AVFoundation 相机功能~~
- ~~CoreML 模型集成~~

如需重新添加这些功能，需要明确讨论和规划。

## 资源文件

### HexagramData.json
包含 64 个卦象的完整数据：
- `id`: 卦序 (1-64)
- `name`: 卦名（如"乾卦"、"坤卦"）
- `hexagramSymbol`: 六爻符号（"阳,阳,阳,阳,阳,阳"）
- `yaos`: 六爻名称数组
- `yaoci`: 爻辞数组
- `divinationDiagramName`: 占卜图名称
- `divinationDiagram`: 占卜图描述
- `explanation`: 卦象解释

### HexagramImages/
64 张卦象图片，命名格式对应卦序

## Git 工作流

- 主分支: `master`
- 功能分支: `codex/` 前缀
- 当前分支: `codex/ios-ondevice-vs-cloud`

## 用户偏好

### 代码风格
- 使用 SwiftUI 原生组件
- 遵循 Swift 命名规范
- 优先使用 `.foregroundColor(.secondary)` 而非硬编码颜色
- 代码注释使用中文

### 测试
- 优先使用 iPhone 15 模拟器
- DEBUG 构建包含测试工具界面
