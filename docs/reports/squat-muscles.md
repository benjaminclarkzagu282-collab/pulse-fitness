# 深蹲肌群表面示意样板

日期：2026-09-28

预览：<http://127.0.0.1:8879/squat-review.html>

在现有六秒深蹲样板上添加三个随蒙皮变形的表面覆盖层：大腿前侧、臀部、腹部与腰背稳定区域。大腿和臀部为橙色，躯干为青绿色。区域边缘采用顶点透明度渐变，底部停顿仍保持显示。选择臀部会自动切换背面；正常人物模式关闭所有覆盖层；切换不改变动作时间。

这是预设的肌群参与区域示意，不是内部肌肉解剖分割、测得的肌力、肌电或个人训练评估。明暗只提示动画阶段，不能用于比较肌群受力大小。臀部覆盖层绘于短裤表面并有对应说明。原动作仍保留待教练复核标记。

## 文件

- 网页：`web/squat-review.html`
- 模型：`web/review/squat-muscles.glb`
- 阶段与区域说明：`web/review/muscle-guidance.mjs`
- 制作脚本：`tools/build_squat_muscles.py`
- 用户可编辑文件：`../characters/03_深蹲动作样板/深蹲_肌群示意.blend`
- 技术检查记录：`docs/reports/squat-muscles-verification.json`
- 浏览器效果：`docs/reports/squat-muscles-desktop.png`、`docs/reports/squat-muscles-mobile.png`

新增 2817 个三角面，源人物网格、贴图和原深蹲动画均未替换。Blender 源文件使用相同静态配色；随阶段变化的透明度由网页控制。保留基线 `squat-v2.glb` 和原始深蹲 Blender 文件。

## 验证

- `python3 tools/verify_squat_muscles.py`：逐属性比较所有原网格、索引和动画通道数据，确认与基线完全一致；检查三层材质、透明度渐变和蒙皮权重，通过。
- `node --test tools/test_muscle_guidance.mjs`：普通模式、底部保持、区域选择、逆向拖动及循环端点，共 4 项通过。
- `git diff --check`：通过。
- 浏览器：1280×960 桌面和 390×844 手机尺寸，普通模式无高亮、恢复模式保持 3.25 秒姿势、臀部自动背面与其他区域淡化、全部区域恢复、上方播放按钮和动作时间推进均检查通过。底部姿势截图已保存。

未进行实体手机帧率测试；这些检查验证显示与数据一致性，不构成专业动作或解剖准确性认证。
