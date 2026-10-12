# 全动作肌群示意实施计划

> **For agentic workers:** Use the approved squat sample as the visual specification. Independent animation, catalog, and viewer work is delegated with separate file ownership; root integrates and verifies every output.

**Goal:** 将用户认可的深蹲肌群表面示意推广到动作库全部 8 个动作，并在 Flutter 动作库与跟练页使用。

**Architecture:** 每个动作保留一个六秒 GLB，额外包含按蒙皮变形的透明区域材质。共享目录描述肌群、角色、阶段和视角，共享 JS 控制器供 Flutter 两平台及独立多视角审看页使用。动作数据与肌群文案分离，暂停、换模式和选区域均不重置动作。

**Tech Stack:** Blender 5.2、glTF、model-viewer、Flutter、Dart、JavaScript。

**Spec:** 用户本轮“就按照你这个 把所有动作都做好”及已认可的 `docs/reports/squat-muscles.md`。

## Global Constraints

- 8 个 ID：squat, pushup, lunge, bridge, plank, row, jumping_jack, curl。
- Exercise 动画统一 6 秒、30 fps、连续闭环；深蹲复用已认可动作。
- 橙色主参与区域，青绿色稳定区域；表面示意，不展示虚构受力百分比。
- 原始人物资源不修改；保留独立深蹲样板；所有制作工具免费本地运行。
- 腕、肘、膝、踝连续；支撑点不穿地；反向弓步包含实际退步和收回。
- 现有 feature/fitness-polish 工作区有未提交成果，原位保留，不切换或清理。

## Task 1: 动作库

**Files:** 新建 `tools/motion_library.py`、`tools/check_motion_library.py`，输出 `.build/motion-library/base/<id>.glb` 与 `.build/motion-library/<id>.blend`。

**Interface:** `pose_exercise(rig, exercise, seconds)`、`animate(rig, exercise)`；Exercise clip 6 s；原人物和哑铃正确绑定。先用旧动作证明几何检查能发现问题，再检查重做导出模型。

- [x] 重做其余七项动作，保留深蹲原姿态。
- [x] 检查实际骨段连续、闭环和支撑，保存证据。
- [x] 保存可编辑模型并预览关键姿势。

## Task 2: 阶段与肌群目录

**Files:** `assets/muscles/catalog.json`、`tools/test_muscle_catalog.mjs`、`docs/reports/muscle-guidance-sources.md`。

**Interface:** 顶层 `{version:1,duration:6,exercises:{id:{name,regions,phases,defaultView,cameraTarget,referenceUrls}}}`；region `{id,name,role,description,view}`；phase `{start,end,label,text}`。

- [x] 根据主要来源定义各动作区域、角色及六秒阶段。
- [x] 验证八个 ID、阶段连续覆盖、区域映射和来源。

## Task 3: App 接入

**Files:** `assets/muscles/controller.js`、Flutter `lib/ui/exercise_*`、`lib/core/muscle_guidance.dart`、`lib/screens/library.dart`、`lib/screens/workout.dart`、相关测试和 pubspec。

**Interface:** `window.PulseMuscles.create(viewer,{catalog,exerciseId,muscles,selectedRegion,playing,speed,orbit,target,onPhase})` 返回 `update(patch)`, `dispose()`, `getState()`。材质名 `PULSE Muscle <id>`。

- [x] 共享控制器切换区域、透明度与说明，底部及静态支撑持续显示。
- [x] Web/原生调用相同控制逻辑，生命周期释放监听，不因普通刷新重置视角。
- [x] 动作库和跟练页支持普通人物／肌群示意、区域选择和阶段文案。
- [x] Flutter 测试与静态分析。

## Task 4: 区域建模、总审看页及交付

**Files:** `tools/build_library_muscles.py`、`tools/verify_library_muscles.py`、`web/exercise-review.html`、`assets/models/athlete_<id>.glb`、交付源文件和报告。

- [x] 从已绑定表面提取区域，渐变透明，复制权重，按各动作目录选择覆盖层。
- [x] 比较覆盖前后原始网格、绑定与动画，验证材料及有限数值。
- [x] 多动作审看页复用同一控制器，双视角、逐帧、阶段定位与切换。
- [x] Flutter web 构建，浏览器检查全部动作、手机版布局、模式切换、阶段切换。
- [x] 独立复核、修复重要问题、保存截图和验证记录。

## Progress

- 2026-09-28：用户已批准沿用深蹲方案；三项独立子任务已分派。Root 负责覆盖层、总审看页与最终集成。

- 已完成：58 项 Flutter 测试、17 项 JavaScript 测试、4 项区域绑定反例测试通过；dart analyze 无问题。8 个模型 27 个区域对比通过。独立代码复核的区域绑定验证缺口已修复并复核通过。
- 最终臀桥降低峰值后重新导出，全库几何检查、区域对比与 web 构建通过。浏览器完成八动作主要姿势、手机地面布局、App 肌群切换、开合跳取景及跟练页验收。交付与边界记录于 `docs/reports/all-exercise-muscles.md`。
