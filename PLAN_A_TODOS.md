# Coin Detection Plan (实时检测 + 模板匹配)

Goal: 端侧实时检测6枚铜钱 + 端侧模板匹配正/反面，支持用户录入模板而无需训练。

## Phase 0: 实时相机流水线
- [ ] AVCaptureSession获取实时帧
- [ ] 推理帧率控制（如15fps），其余帧丢弃
- [ ] Vision请求队列串行化，避免积压

## Phase 1: Coin Detection（目标检测 + 规则筛选）
- [ ] 导入/训练coin目标检测模型（Create ML Object Detector或YOLO导出Core ML）
- [ ] VNCoreMLRequest获取候选框和置信度
- [ ] 过滤低置信度/面积离群候选
- [ ] 垂直一列约束（cx集中、cy间距均匀、不重叠）
- [ ] 评分函数选最优6枚并按cy排序输出1-6
- [ ] UI失败提示（不足6枚/不够垂直/遮挡）

## Phase 2: 模板录入 + FeaturePrint匹配
- [ ] 录入正/反模板（单枚引导框、裁剪、居中、缩放、圆形mask）
- [ ] VNGenerateImageFeaturePrintRequest生成模板特征并持久化
- [ ] 每个ROI生成特征，与正/反模板距离比较
- [ ] 输出front/back/uncertain，基于距离差计算置信度
- [ ] 阈值标定与不确定区间（样本统计分布）

## Phase 3: 鲁棒性与性能优化
- [ ] 支持多模板（正/反各多张取最小距离）
- [ ] 时间平滑（投票/指数平滑）降低闪烁
- [ ] 检测模型量化/剪枝（低端机优化）
- [ ] 失败兜底（连续uncertain提示重录模板/改善光照）
