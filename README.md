# 起的课 - iOS Application

## 项目概述

这是一个基于模板匹配算法的中国传统金钱卦识别iOS应用，使用SwiftUI、Vision Framework和SwiftData构建。

## 技术架构

### 核心技术栈
- **UI框架**: SwiftUI
- **图像识别**: Vision Framework (目标检测 + Feature Print模板匹配)
- **相机功能**: AVFoundation
- **数据存储**: SwiftData
- **部署目标**: iOS 16+
- **开发环境**: Xcode 14+

### 项目结构

```
TianjiApp/
├── App/                          # 应用入口和主界面
│   ├── TianjiApp.swift           # App主入口
│   └── ContentView.swift           # 主界面
├── Camera/                       # 相机相关组件
│   ├── CameraManager.swift         # 相机管理器
│   ├── CameraPreview.swift         # 相机预览组件
│   └── CameraOverlay.swift         # 6槽位覆盖层
├── Recognition/                  # 图像识别模块
│   ├── TemplateManager.swift       # 模板管理
│   ├── ROICropper.swift          # ROI裁剪
│   ├── FeatureMatchService.swift   # 特征匹配服务
│   └── CoinValidator.swift        # 铜钱验证
├── Data/                         # 数据层
│   ├── Models/                   # 数据模型
│   │   ├── CoinProfile.swift       # 铜钱配置
│   │   ├── DivinationSession.swift # 起课记录
│   │   ├── CoinResult.swift       # 识别结果
│   │   └── Hexagram.swift       # 卦象数据
│   └── SwiftData/               # SwiftData配置
│       ├── TianjiSchema.swift
│       └── PersistenceController.swift
├── Views/                        # 视图组件
│   ├── SetupProfileView.swift     # 模板设置
│   ├── CameraView.swift          # 相机界面
│   ├── HistoryView.swift          # 历史记录
│   └── ResultView.swift          # 结果显示
├── Utils/                        # 工具类
│   ├── ImageProcessor.swift      # 图像处理
│   └── ConfidenceCalculator.swift # 置信度计算
├── Resources/                    # 资源文件
│   ├── HexagramData.json       # 64卦数据
│   └── Assets.xcassets        # 应用资源
└── TianjiApp.xcodeproj/      # Xcode项目文件
```

## 核心功能

### 1. 铜钱模板设置
- 用户录入正面/反面模板照片（可多张，建议不同光照/角度）
- 录入时对单枚铜钱做引导裁剪与标准化，生成Feature Print特征
- 模板数据存储在SwiftData中

### 2. 图像识别流程
1. 相机实时帧输入
2. 目标检测模型输出coin候选框（VNCoreMLRequest）
3. 规则筛选与评分，选出最优6枚并按垂直一列排序
4. 对每个ROI做标准化处理，生成Feature Print
5. 与正/反模板特征计算距离，输出正/反/不确定
6. 时间平滑与置信度校验
7. 生成6爻数组并转换为卦象

### 3. 卦象转换和显示
- 将6爻数组映射到64卦之一
- 显示卦名、卦图、爻词
- 展示占卜图解和文字解释
- 保存历史记录

## 数据模型

### CoinProfile (铜钱配置)
```swift
- id: UUID
- name: String                    // 配置名称
- frontTemplates: Data             // 字面模板特征
- backTemplates: Data              // 图案面模板特征
- createdDate: Date
```

### DivinationSession (起课记录)
```swift
- id: UUID
- date: Date                     // 起课时间
- source: String                  // 来源(camera/photo)
- profileId: UUID                // 使用的模板ID
- results: [CoinResult]?          // 识别结果
- imagePaths: [String]?          // 图片路径
- roiPaths: [String]?           // ROI路径
```

### CoinResult (识别结果)
```swift
- position: Int                   // 爻位(1-6)
- yinYang: YinYang               // 阴阳属性
- side: CoinSide                 // 正反面
- confidence: Double             // 置信度(0.0-1.0)
```

## 识别算法

### 两阶段流水线（推荐）
1. **目标检测**: 使用自定义检测模型定位6枚铜钱（VNCoreMLRequest）
2. **规则筛选**: 过滤低置信度/面积离群候选
3. **几何约束**: 垂直一列对齐、间距均匀、不重叠
4. **特征匹配**: ROI生成Feature Print，与正/反模板计算距离
5. **置信度与不确定**: 距离差过小则输出uncertain，提示重新摆放或录入模板

### 模板匹配流程
1. **特征提取**: VNGenerateImageFeaturePrintRequest生成视觉特征
2. **ROI裁剪**: 由检测框裁剪ROI并做居中/缩放/圆形mask
3. **特征匹配**: 计算ROI特征与模板特征的距离
4. **置信度计算**: 基于距离差值计算识别置信度
5. **结果判定**: 距离差值过小进入不确定区间

### 置信度计算
```swift
confidence = 1.0 - (min_distance / total_distance)
side = front_distance < back_distance ? front : back
```
注：阈值需要用样本标定，不同iOS版本/机型的Feature Print距离分布可能不同。

## 用户界面

### 主界面
- 设置铜钱模板
- 开始起课
- 历史记录

### 相机界面
- 实时相机预览
- 6个垂直排列的槽位overlay
- 拍照和识别按钮
- 处理进度显示

### 结果界面
- 卦象信息显示
- 六爻排列
- 爻词显示
- 占卜图解展示
- 卦象解释文本

### 历史记录
- 按时间排序的起课记录
- 详细信息查看
- 记录删除功能

## 性能指标

### 目标性能
- **识别速度**: <1秒/张图片
- **准确度**: 85-95%
- **内存占用**: <100MB
- **模板设置**: 2-3分钟完成

### 优化策略
- 异步图像处理
- 并发特征匹配
- 高效的数据结构
- 内存缓存优化

## 开发状态

### ✅ 已完成
- [x] 项目架构设计
- [x] 64卦数据准备
- [x] iOS项目基础结构
- [x] 相机预览和槽位UI
- [x] ROI裁剪和模板匹配功能
- [x] 数据持久化
- [x] 卦象转换和结果显示

### 📋 待完善
- [ ] 真机测试和调试
- [ ] 性能优化
- [ ] 错误处理完善
- [ ] 用户引导和帮助
- [ ] 占卜图高清版本集成

## 构建和运行

### 前置条件
- macOS 13+ with Xcode 14+
- iOS 16+ 设备用于相机功能测试
- 开发者账号用于真机调试

### 构建命令
```bash
# 模拟器构建
xcodebuild -project TianjiApp.xcodeproj -scheme TianjiApp -sdk iphonesimulator build

# 真机构建
xcodebuild -project TianjiApp.xcodeproj -scheme TianjiApp -sdk iphoneos build

# 运行测试
xcodebuild test -project TianjiApp.xcodeproj -scheme TianjiApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 注意事项

### 权限配置
需要在Info.plist中配置：
- `NSCameraUsageDescription`: 相机访问权限
- `NSPhotoLibraryUsageDescription`: 相册访问权限

### 设备要求
- 推荐iPhone 12及以上设备
- 需要后置摄像头
- iOS 16.0+

### 已知限制
- 目前仅支持单个铜钱配置
- 占卜图为文字描述，需要集成高清图片
- 真机测试未完成，可能存在兼容性问题

## 未来扩展

### 短期计划
- [ ] 占卜图高清图片集成
- [ ] 相册图片选择支持
- [ ] 多铜钱配置支持
- [ ] 历史记录导出功能

### 长期规划
- [ ] iCloud数据同步
- [ ] Apple Watch支持
- [ ] 占卜结果分享功能
- [ ] 用户社区和经验分享

## 许可证

本项目为个人学习和研究用途。

## 联系方式

如有问题或建议，请联系开发者。
