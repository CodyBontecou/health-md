---
title: 可视化与路线图
description: 按导出数据类型整理的 Health.md Obsidian 当前可视化覆盖范围与规划图表。
---

Health.md 可将带有架构版本的数据集以本地方式导出为 Markdown、Obsidian Bases、JSON 和 CSV。以下可视化路线图将这些数据与配套的 Obsidian 可视化插件关联起来：目前已有的功能、导出数据接下来可以支持的功能，以及哪些类别需要通用的架构感知图表。

<div class="callout">
<strong>数据来源。</strong>
<p style="margin-top:6px;">本页依据 Health.md 的导出架构和数据字典整理，涵盖活动、睡眠、心脏、生命体征、身体、营养、正念、药物、锻炼、生殖健康、症状、听力以及生活方式/环境指标。</p>
</div>

## 当前可视化覆盖范围

<div class="reference-stats">
<div><strong>43</strong><span>个现有插件渲染器</span></div>
<div><strong>18</strong><span>个导出数据类别</span></div>
<div><strong>220+</strong><span>个规范导出键</span></div>
<div><strong>1</strong><span>个仍需实现的通用指标层</span></div>
</div>

## 各导出器的平台支持

可视化支持取决于源数据是同时存在于 Apple HealthKit 和 Android Health Connect 中，还是仅存在于 Apple HealthKit 导出协议中。

### iOS 和 Android

这些可视化对应 HealthKit / Health Connect 共享的导出字段：

| 类别 | 可视化类型 |
| --- | --- |
| 概览 | `intro-stats`、`summary-card`、`trend-tile` |
| 活动 | `activity-rings`、`vitals-rings`、`bar-chart`、`activity-heatmap`、`step-spiral`、`weekday-average` |
| 心脏 | `heart-terrain`、`heart-range`、`hrv-trend` |
| 呼吸与生命体征 | `oxygen-river`、`oxygen-range`、`breathing-wave` |
| 睡眠 | `sleep-schedule`、`sleep-quality-bars`、`sleep-architecture`、`sleep-polar` |
| 行动能力 | `walking-symmetry`* |
| 锻炼 | `workout-log`、`workout-heart-rate`、`workout-zones`、`workout-trends`、`workout-intervals`、`workout-map` |

说明：

- `walking-symmetry` 在 Android 上仅部分支持：Android 提供步行速度，但不提供 Apple 独有的步态不对称或双支撑期详情。
- `activity-rings` 的站立功能在 Android 上仅部分支持：如果缺少 `standHours`，插件会改用根据步数推算的站立替代值。
- 锻炼路线和样本图表需要精细锻炼数据，以及路线权限/用户同意。

### 仅 iOS

HealthKit 心境/情绪可视化：

- `mood-trend` / `state-of-mind`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

药物目录/服药事件可视化：

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connect 不提供与 HealthKit 心境记录或 HealthKit 风格药物目录/服药事件记录等效的数据。

### 仅 Android

当前 Obsidian 插件的可视化注册表中没有仅限 Android 的可视化。Android 会导出 PHR/FHIR 资源、计划锻炼和活动强度等 Android 原生数据，但目前尚无可视化类型使用这些字段。

<span id="visualization-screenshot-gallery"></span>

## 可视化目录

每个项目都链接到 [Health.md 可视化图库](/visualizations/)中对应的公开变体。这些链接使用 `theme-colors` 变体，使文档保持快速、稳定，而不是在本页嵌入所有渲染器。

### 摘要与概览

- [概览统计](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [摘要卡片](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [趋势磁贴](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### 活动

- [活动圆环](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [条形图](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [活动热力图](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [步数螺旋图](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [星期平均值](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### 心脏

- [心率地形图](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [心率范围](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [HRV 趋势](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### 呼吸、血氧与生命体征

- [血氧河流图](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [血氧范围](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [呼吸波形图](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [生命体征圆环](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### 睡眠

- [睡眠时间表](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [睡眠质量条形图](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [睡眠结构](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [睡眠极坐标图](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### 正念与情绪

- [情绪趋势](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [情绪日历热力图](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [情绪 × 睡眠散点图](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [情绪日内时间线](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [按关联因素划分的情绪](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [情绪标签云](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [情绪波动](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [每日情绪与即时情绪](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [昼夜节律情绪时钟](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [恢复 + 心态磁贴](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [情绪关联矩阵](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### 药物

- [药物概览](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [药物清单](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [用药依从性摘要](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [服药状态](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [用药依从性趋势](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [近期服药事件](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### 行动能力、步态与跑姿

- [步态对称性](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### 锻炼

- [锻炼日志](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [锻炼心率](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [锻炼心率区间](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [锻炼趋势](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [锻炼间歇](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [锻炼地图](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## 基础能力路线图

最大的产品缺口并非某一张缺失的图表，而是一个通用的架构感知指标层。它应当允许绘制任意 Health.md 导出字段，而不必为每个指标分别编写自定义解析器和渲染器。

### 已实现

- 支持每日导出、旧版文件、汇总文件和数据字典文件的架构兼容性检测。
- 支持加载 JSON、CSV、Markdown 和 Obsidian Bases。
- 可识别汇总文件，避免每周/每月/每年摘要污染每日图表。
- 支持从图表数据点跳转到对应的 Health.md 源文件。

### 规划中

- **通用架构感知指标访问器** — 读取 `_healthmd_data_dictionary.json` 中的标签、单位、类别、聚合规则和别名。
- **通用指标趋势图** — 为任意数值型导出键生成折线图/面积图。
- **通用指标条形图** — 通用的每日/每周/每月条形图，支持目标线和阈值线。
- **通用日历热力图** — 将任意每日数值指标显示为日历网格。
- **可视化覆盖报告** — 显示知识库中存在的字段，以及专用渲染器已覆盖的字段。

---

## 摘要与概览

### 已实现

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — 显示总计、平均值、睡眠和生命体征的数据集摘要。
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — Apple 风格的 KPI 卡片，包含迷你趋势图和上一周期对比。
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — 对比当前时间窗口与上一时间窗口的趋势卡片。

### 规划中

- 根据所选 Health.md 文件夹中的字段自动生成仪表板。
- 按数据类别显示架构覆盖情况的仪表板。
- 相关性摘要卡片，例如睡眠与情绪、HRV 与锻炼、症状与药物，或酒精与睡眠。

---

## 活动

Health.md 会导出步数、活动能量、静息能量、锻炼时间、站立时间、已爬楼层、步行/跑步距离、骑行、游泳、轮椅活动、下坡雪上运动距离、活动时间、体力强度和最大摄氧量。

### 已实现

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### 规划中

- 汇总步数、卡路里、锻炼、站立小时数和体力强度的活动负荷仪表板。
- 最大摄氧量趋势。
- 活动/锻炼/站立一致性图表。
- 步行/跑步、骑行、游泳、轮椅和雪上运动的距离构成图。
- 游泳距离 + 划水次数图表。
- 轮椅距离 + 推动次数图表。

---

## 睡眠

Health.md 会导出总睡眠时长、就寝时间、起床时间、深度睡眠/REM/核心睡眠/清醒/卧床时长，以及精细睡眠阶段区间。

### 已实现

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### 规划中

- 睡眠负债与规律性评分。
- 睡眠阶段占比趋势。
- 就寝/起床规律性热力图。
- 睡眠 + HRV + 静息心率恢复仪表板。

---

## 心脏

Health.md 会导出静息心率、步行心率、平均/最低/最高心率、HRV、心率样本、HRV 样本、心率恢复和房颤负荷。

### 已实现

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### 规划中

- 静息心率趋势。
- 步行心率趋势。
- 心率恢复趋势。
- 房颤负荷图表。
- HRV + 静息心率恢复磁贴。
- 按时段显示的昼夜节律心率曲线。

---

## 呼吸与血氧

Health.md 会导出平均/最低/最高血氧、血氧样本、平均/最低/最高呼吸频率和呼吸频率样本。

### 已实现

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### 规划中

- 专用呼吸频率范围图。
- 血氧饱和度下降事件图。
- 结合睡眠阶段、血氧和呼吸频率的夜间呼吸仪表板。

---

## 生命体征

Health.md 会导出体温、血压、血糖、基础体温、手腕温度、皮电活动、用力肺活量、FEV1、呼气峰值流量和吸入器使用情况。

### 已实现

- 通过摘要卡片和通用每日图表提供部分支持。

### 规划中

- 带阈值区间的收缩压/舒张压范围图。
- 血糖范围图。
- 体温、基础体温和手腕温度趋势。
- 手腕温度恢复/疾病磁贴。
- 汇总 FVC、FEV1、呼气峰值流量和吸入器使用情况的呼吸功能仪表板。
- 皮电活动/压力趋势。

---

## 身体测量

Health.md 会导出体重、身高、BMI、体脂率、去脂体重和腰围。

### 已实现

- 尚无专用身体成分渲染器。

### 规划中

- 身体成分仪表板。
- 带移动平均线和目标线的体重趋势。
- 带类别区间的 BMI 趋势。
- 体脂与去脂体重图表。
- 腰围趋势。

---

## 行动能力、步态与跑姿

Health.md 会导出步行速度、步长、双支撑期、步态不对称、上楼/下楼速度、六分钟步行距离、步行稳定性、跑步速度、跑步步幅、触地时间、垂直振幅和跑步功率。

### 已实现

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### 规划中

- 步态仪表板。
- 步行稳定性仪表。
- 六分钟步行趋势。
- 上楼/下楼速度图表。
- 汇总速度、步幅、触地时间、垂直振幅和功率的跑姿仪表板。

---

## 锻炼

Health.md 会导出锻炼次数、分钟数、卡路里、距离、锻炼类型、心率统计、跑步/骑行姿态指标、功率、海拔、圈数、分段、路线点、心率区间和锻炼时间序列样本。

### 已实现

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### 规划中

- 锻炼日历热力图。
- 根据时长和强度计算的训练负荷图。
- 按类型划分的每周锻炼分布。
- 按锻炼类型划分的配速和速度趋势。
- 累计爬升/下降趋势。
- 路线对比小多图。
- 功率曲线/最佳表现。
- 跑姿和骑行表现仪表板。

---

## 正念与情绪

Health.md 会导出正念分钟数、正念时段、心境条目、平均情绪效价、每日情绪、即时情绪、标签和关联因素。

### 已实现

- [`mood-trend`](/visualizations/mindfulness-mood/mood-trend/theme-colors/)
- [`mood-calendar-heatmap`](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/)
- [`mood-sleep-scatter`](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/)
- [`mood-day-timeline`](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/)
- [`mood-association-breakdown`](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/)
- [`mood-label-cloud`](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/)
- [`mood-volatility`](/visualizations/mindfulness-mood/mood-volatility/theme-colors/)
- [`mood-kind-split`](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/)
- [`mood-circadian-clock`](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/)
- [`mood-recovery-tile`](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/)
- [`mood-association-matrix`](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/)

### 规划中

- 正念分钟数趋势。
- 正念会话连续记录/日历。
- 情绪与用药依从性。
- 情绪与营养、酒精及咖啡因。
- 情绪标签时间线。

---

## 药物

Health.md 会导出药物清单、在用/已归档数量、服药事件数量、已服用/已跳过数量、药物详情、RxNorm/编码元数据、剂量、计划类型、计划/开始/结束日期、状态和元数据。

### 已实现

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### 规划中

- 用药计划时间线。
- 用药依从性日历热力图。
- 对比计划时间与实际服药时间的延迟图。
- 剂量趋势。
- 药物与症状/情绪关联视图。
- RxNorm/编码详情面板。

---

## 营养

Health.md 会导出膳食卡路里、蛋白质、碳水化合物、脂肪、饱和脂肪、单不饱和脂肪、多不饱和脂肪、膳食纤维、糖、钠、胆固醇、水和咖啡因。

### 已实现

- 尚无专用营养渲染器。

### 规划中

- 营养仪表板。
- 宏量营养素构成图。
- 摄入卡路里与活动卡路里图。
- 水分摄入趋势。
- 每日咖啡因摄入量/时间图。
- 糖和钠阈值图。
- 膳食纤维和蛋白质目标进度。

---

## 维生素与矿物质

Health.md 会导出维生素 A、B6、B12、C、D、E、K、硫胺素、核黄素、烟酸、叶酸、生物素、泛酸、钙、铁、钾、镁、磷、锌、硒、铜、锰、铬、钼、氯和碘。

### 已实现

- 尚无专用微量营养素渲染器。

### 规划中

- 微量营养素热力图。
- 每日推荐摄入量进度网格。
- 维生素趋势仪表板。
- 矿物质趋势仪表板。
- 缺乏/过量标记面板。
- 营养完整性评分。

---

## 听力

Health.md 会导出耳机音频音量和环境声音音量。

### 已实现

- 仅提供部分摘要级支持。

### 规划中

- 听力暴露趋势。
- 高音量日期日历。
- 安全暴露阈值区间。
- 每周暴露摘要。

---

## 生殖健康与周期追踪

Health.md 会导出月经流量、性活动、排卵测试结果、宫颈黏液质量和经间期出血。

### 已实现

- 尚无专用生殖健康渲染器。

### 规划中

- 周期日历。
- 月经流量热力图。
- 生育信号时间线。
- 结合生殖健康、症状、情绪和睡眠的周期症状叠加图。
- 点滴出血/经间期出血时间线。

---

## 症状

Health.md 会导出以下症状的每日计数：头痛、疲劳、恶心、头晕、情绪变化、睡眠变化、食欲变化、潮热、发冷、发热、下背痛、腹胀、便秘、腹泻、胃灼热、咳嗽、咽喉痛、流鼻涕、气短、胸痛、心搏脱漏、心动过速、痤疮、皮肤干燥、脱发、记忆衰退、盗汗、呕吐、腹部痉挛、乳房疼痛、盆腔疼痛、身体酸痛、昏厥、嗅觉丧失、味觉丧失、喘息、鼻窦充血、尿失禁和阴道干涩。

### 已实现

- 尚无专用症状渲染器。

### 规划中

- 症状日历热力图。
- 症状频率排行榜。
- 症状共现矩阵。
- 症状发作时间线。
- 症状相关性探索器。
- 按身体系统分组的症状仪表板。

---

## 其他健康、生活方式与环境数据

Health.md 会导出紫外线暴露、日照时间、跌倒、血液酒精浓度、酒精饮品、胰岛素输送、刷牙、洗手、水温和水下深度。

### 已实现

- 尚无专用生活方式/环境渲染器。

### 规划中

- 日照/紫外线日历。
- 跌倒时间线。
- 酒精与睡眠/HRV 图表。
- 胰岛素输送趋势。
- 刷牙和洗手连续记录。
- 水温/水下深度图表。

---

## 优先顺序

1. 通用架构感知指标基础设施。
2. 通用趋势图、条形图和日历热力图渲染器。
3. 生命体征套件：血压、血糖、体温、呼吸功能。
4. 身体成分仪表板。
5. 营养仪表板。
6. 症状热力图、排行榜和相关性视图。
7. 周期/生殖健康日历。
8. 微量营养素热力图和 RDA 网格。
9. 扩展的行动能力和跑姿仪表板。
10. 听力和生活方式/环境图表。

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">最后更新于 2026-06-25</p>
