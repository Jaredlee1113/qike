# TianjiApp 当前进度（会话接力文档）

更新日期：2026-02-27

## 1. 本轮改造目标
- 从“固定槽位裁剪”为主，切换为“自动检测6枚铜钱”为主。
- 检测失败或判定不稳定时，提供“仅拖动”的微调流程。
- 模板升级为高质量版本（descriptor + FeaturePrint + 单币检测裁剪）。
- 旧模板（缺 FeaturePrint / descriptor）识别时提示重录模板；仅缺 ring descriptor 时允许自动补齐。
- 保持端侧离线识别，不接云端。

## 2. 已完成项

### 2.1 识别主流程改造（Camera）
- 拍照识别主路径已切换为 `CoinDetector.detectCoins(from:)` 自动检测。
- 识别流程现为：
  - 自动检测 -> 质量筛选 -> 模板匹配 -> 可靠性判断
  - 失败则进入微调页，而不是直接报错结束。
- 关键文件：
  - `Views/CameraView.swift`
  - `Recognition/CoinDetector.swift`

### 2.2 微调流程（仅拖动）
- 新增 `CoinAdjustView`：
  - 输入：原图 + 初始检测框
  - 操作：只允许拖动框，不允许缩放
  - 输出：按 `y` 坐标重新排序为 `6 -> 1` 后再识别
- 关键文件：
  - `Views/CoinAdjustView.swift`
  - `Recognition/DetectionDraft.swift`
  - `Recognition/ROICropper.swift`

### 2.3 ROI 重建能力
- `ROICropper` 已新增：
  - `drafts(from:)`
  - `defaultDrafts(in:)`
  - `detections(from:image:)`
- 用于将微调框重建为 `DetectedCoin` 并统一排序映射。

### 2.4 模板升级与兼容策略
- `TemplateManager.TemplateData` 已新增 `version` 字段：
  - 新模板默认 `version = 3`
  - 旧模板反序列化默认 `version = 1`
- 识别时若命中以下任一条件，提示“模板版本过旧，请重录模板”：
  - `version < 2`
  - FeaturePrint 缺失
  - descriptor 缺失
- 关键文件：
  - `Recognition/TemplateManager.swift`
  - `Views/SetupProfileView.swift`
  - `Views/CameraView.swift`

### 2.5 回退开关（feature flag）
- 默认启用新流程（自动检测流）。
- 可回退旧流程：
  - 启动参数：`-force-legacy-detection-flow`
  - `UserDefaults`：`feature_auto_detection_flow_enabled = false`
- 关键文件：
  - `Views/CameraView.swift`

### 2.6 Xcode 工程接入
- 新增文件已加入 target：
  - `Views/CoinAdjustView.swift`
  - `Recognition/DetectionDraft.swift`
- 关键文件：
  - `TianjiApp.xcodeproj/project.pbxproj`

### 2.7 拍照入口与微调兜底修复（新增）
- 相机页新增主按钮“拍照识别”，明确以“拍照后识别”驱动流程，不依赖实时检测自动跳转。
- `CameraManager` 新增 `capturePhotoWithResult`，支持拍照失败回调，避免无响应。
- 去掉 `DEBUG` 下自动检测失败时回退固定槽位 6 枚的逻辑，避免“看起来是 6 枚但实际定位错误”。
- 匹配结果为空时不再静默结束，统一进入微调页（`reliabilityRejected`）。
- 关键文件：
  - `Views/CameraView.swift`
  - `Camera/CameraManager.swift`

### 2.8 微调框统一尺寸（新增）
- 微调页 6 个识别框改为统一尺寸，不再使用自动检测原始框大小（避免“大有小有”影响对齐体验）。
- 统一尺寸策略：
  - 以检测框尺寸中位数为主
  - 以默认槽位尺寸中位数为约束
  - 最终做边界裁剪，保证拖动不越界
- 关键文件：
  - `Views/CameraView.swift`

### 2.9 匹配阈值稳健化（新增）
- 修复 `Confidence: invalid match minDistance=...` 大量出现导致无法进入确认页的问题。
- `FeaturePrint` 距离策略调整：
  - 校准阈值增加合理下限/上限（避免模板过“紧”时误判大量 invalid）
  - 超阈值由直接 `invalid` 改为 `uncertain`，保留后续融合机会
- `Descriptor` 策略调整：
  - 校准后的 `minScore/minGap` 由“激进”改为稳健区间
  - `invalid` 判定阈值下探，降低误杀
  - 当 descriptor 明确但 feature 为 invalid 时，允许 descriptor 兜底
- 关键文件：
  - `Utils/ConfidenceCalculator.swift`
  - `Recognition/FeatureMatchService.swift`

### 2.10 极坐标展开与文字环特征（新增）
- 新增“文字环”特征提取：
  - 对铜钱做极坐标展开（polar unwrap），把圆环文字摊平成条带
  - 提取环带强度 + 边缘 profile，形成 ring descriptor
- 模板结构新增 `ringDescriptors`，新模板默认写入。
- 识别融合升级为三路证据：
  - FeaturePrint
  - 原 descriptor
  - ring descriptor（文字环）
- 旧模板兼容：
  - 若模板中缺少 ring descriptor，识别时会尝试用 profile 预览图自动补齐并回写模板数据（无需手动重录）。
- FeaturePrint 匹配新增旋转变体（0/90/180/270）以增强角度鲁棒性。
- 关键文件：
  - `Utils/ImageProcessor.swift`
  - `Recognition/TemplateManager.swift`
  - `Recognition/FeatureMatchService.swift`
  - `Views/CameraView.swift`

### 2.11 微调后确认页兜底（新增）
- 解决“微调后仍无法进入确认页”的卡死体验：
  - 微调后重识别若未通过严格可靠性，也会在“6枚位置齐全”时进入确认页供人工确认。
  - 识别结果中的 `invalid` 在微调确认场景会降级为 `uncertain` 占位，不再强制打回微调页。
  - 若匹配结果为空但已有 6 枚 ROI，则用 `uncertain` 占位结果进入确认页。
- 自动流程仍保持“准确优先”的严格门槛，兜底仅用于“用户已进入微调并手动拖框后”的二次识别路径。
- 关键文件：
  - `Views/CameraView.swift`

### 2.12 二次精裁后再匹配（新增）
- 在模板匹配前新增“单币二次重定位”步骤：
  - 对每个 ROI（优先 masked 图）调用 `detectSingleCoinFast` 做二次裁切/居中。
  - 以二次精裁结果生成缩放候选 + 光照候选，再进入 FeaturePrint/descriptor/ring 三路融合。
- 目的：降低初次检测框偏移、背景混入导致的随机匹配。
- 关键文件：
  - `Views/CameraView.swift`

### 2.13 增强版判定引擎（新增）
- 新增“文字感知通道”（端侧 Vision）并融合到最终判定：
  - 对铜钱做极坐标环带图（polar ring）和整币图两路文字信号提取。
  - 使用 `VNRecognizeTextRequest + VNDetectTextRectanglesRequest` 计算文字存在分数。
  - 通过模板预览图自动校准 front/back 的文字分布阈值（按 profile 缓存）。
- 新增“可插拔 CoreML 二分类通道”：
  - 若包内存在 `CoinSideClassifier.mlmodelc`，自动启用模型分类并参与融合。
  - 若不存在模型文件，静默回退到现有规则引擎（无需改配置）。
- 当前融合由三路升级为“多路融合”：
  - FeaturePrint + descriptor + ring descriptor + text evidence (+ optional CoreML)。
- 关键文件：
  - `Recognition/FeatureMatchService.swift`
  - `Views/CameraView.swift`

### 2.14 确认即采样 + 增量模板学习（新增）
- 在确认页点击“确认”后，自动把本次 6 枚铜钱按最终阴阳标签回灌到模板库：
  - `front` 结果写入 front 模板
  - `back` 结果写入 back 模板
- 增量内容包含三类特征：
  - FeaturePrint
  - descriptor
  - ring descriptor
- 每侧模板样本做上限裁剪（默认 120），防止无限增长导致性能和存储劣化。
- 目的：用真实使用过程自然积累高质量标注样本，不依赖一次性大量数据。
- 关键文件：
  - `Views/CameraView.swift`
  - `Recognition/TemplateManager.swift`

### 2.15 槽位引导检测 + 匹配稳健化（新增）
- 检测阶段已改为“槽位引导优先”：
  - 根据相机页两条竖向槽位线，映射出图片中的引导列区域。
  - `CoinDetector.detectCoins` 新增 `focusRegionNormalized`，优先在该区域内筛选候选，再做 6 枚组合选择。
  - 目的：减少全图误检导致的偏移，提升“检测框贴合槽位列”的稳定性。
- 严格模式（默认开启）：
  - 改为按 6 个槽位逐格检测（每槽局部单币检测），并直接返回槽位检测结果，不再回退全图候选。
  - 可通过 `-disable-strict-slot-detection` 或 `feature_strict_slot_detection_enabled=false` 临时关闭。
- 正反匹配稳健化：
  - descriptor 与 ring descriptor 匹配由“单模板最佳分”改为“Top-K 平均分”（默认 K=5）。
  - 目的：降低离群模板造成的随机波动，提升 front/back 判定一致性。
- 关键文件：
  - `Recognition/CoinDetector.swift`
  - `Views/CameraView.swift`
  - `Recognition/FeatureMatchService.swift`
  - `Recognition/ROICropper.swift`

### 2.16 增量学习防污染（新增）
- 确认即采样策略增加样本质量门槛：
  - 仅当“建议结果为 front/back 且与最终确认一致，且置信度 >= 0.72”时，才写入增量模板。
  - 对 `uncertain/invalid` 或低置信建议，不再入库，避免错误标签放大导致结果随机。
- 关键文件：
  - `Views/CameraView.swift`

### 2.17 拍照视野对齐 + 槽位列先裁整图（新增）
- 修复“拍照结果视野大于预览”的问题：
  - 拍照后先按预览可见区域（`resizeAspectFill`）对原图裁切，再进入识别流程。
- 槽位检测进一步收紧：
  - 先按两条槽位线对应的列区域裁整图（column crop）。
  - 再在列区域内按 6 个槽位逐格做单币检测与回映射，严格限制检测不越出槽位列。
- 关键文件：
  - `Views/CameraView.swift`
  - `Recognition/ROICropper.swift`

### 2.18 一键清空增量样本（新增）
- `CoinProfile` 新增初始模板快照字段：
  - `baseFrontTemplates`
  - `baseBackTemplates`
- 模板中心新增“清空增量样本”入口：
  - 优先使用模板预览图重建干净模板并覆盖当前模板。
  - 若预览图不可用，则回退到初始模板快照。
- 关键文件：
  - `Data/Models/CoinProfile.swift`
  - `Data/Storage/DataStorageManager.swift`
  - `Views/TemplateCenterView.swift`

### 2.19 槽位检测再收紧（新增）
- 严格槽位模式在常规运行下默认强制开启（仅保留启动参数 `-disable-strict-slot-detection` 用于临时调试关闭）。
- 检测流程进一步改为硬约束两阶段：
  - 先求 6 槽位并合并为 `columnRect`，先裁出槽位列区域（column crop）。
  - 再在每个槽位局部 patch 内做单币检测，检测结果映射回原图后强制 clamp 在槽位内。
- 识别框统一为方形固定比例：
  - 每个槽位最终 ROI 使用相同侧长比例（默认 `slotSide * 0.88`），减少大小波动带来的匹配不稳定。
- 新增调试日志：
  - `slot column crop x/y/w/h`
  - `slot N local detected -> rect ...`
  - `slot N fallback rect ...`
- 关键文件：
  - `Views/CameraView.swift`

## 3. 本轮代码清单（关键）
- `Views/CameraView.swift`
- `Views/CoinAdjustView.swift`（新增）
- `Recognition/DetectionDraft.swift`（新增）
- `Recognition/ROICropper.swift`
- `Recognition/TemplateManager.swift`
- `Views/SetupProfileView.swift`
- `TianjiApp.xcodeproj/project.pbxproj`

## 4. 当前识别策略（准确优先）
- `uncertain/invalid` 仍严格处理，不放宽到“先给结果再说”。
- 只有“6枚齐全 + 可靠性通过”才进入最终确认页。
- 不满足条件进入微调页或提示重拍/重录模板。
- 当前融合策略：FeaturePrint + descriptor + ring descriptor + text evidence + (optional CoreML)。
- 当前学习策略：确认页人工结果会反哺模板，形成端侧增量学习闭环。

## 5. 验证结果
- iOS 构建验证通过：
  - 命令：`xcodebuild -project TianjiApp.xcodeproj -scheme TianjiApp -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
  - 结果：`BUILD SUCCEEDED`
- 本轮修复相关文件（`CameraView.swift`、`CameraManager.swift`）均通过编译。

## 6. 已知待办（下一轮建议）
- 真机回归验证指标：
  - 自动一次命中6枚比例
  - 进入微调页比例
  - 微调后完成率
  - 正反误判率
- UI 微调：
  - 微调页可考虑增加“重置到自动检测结果”按钮
  - 微调页可视化提示可再增强（例如高亮顺序线）
- 若快速版指标未达标，再进入增强版：
  - 增加端侧 Core ML 正反分类模型，与现规则融合。

## 7. 新开对话建议最小上下文
- 请直接提供：
  - 本文件 `PROJECT_PROGRESS.md`
  - 你的新目标（例如“继续做增强版”或“先做真机验收”）
  - 当前遇到的问题现象（可附 2~3 张失败样例图）
