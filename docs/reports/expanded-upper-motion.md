# 8 个上肢与髋铰链动作扩充

保留 `.build/realistic-character/athlete-source.blend` 的原始角色、蒙皮和 53 骨骨架，新增 `tools/motion_upper.py`。共享 runner 负责每个动作 6 秒、30 fps、181 个 LINEAR 关键帧，动画名 `Exercise`。这些是按动作资料制作的参考动画，不是动作捕捉或真人教练认证。

动作均已生成 `.build/motion-library/<id>.blend`、`base/<id>.glb`，以及 `renders/<id>-start.png`、`-middle.png`、`-end.png`。起始/峰值画面已人工读图；上斜、跪姿、单臂划船、RDL 还增加了带地面的侧面 QA 图。QA 地面不写入交付 GLB。

| ID | 动作与本次实现 | 官方/一手参考 |
|---|---|---|
| kneeling_pushup | 双掌、双膝支撑，躯干与大腿整体降低；小腿抬起；膝盖接触随真实膝前皮肤滚动，水平锚点固定 | [ACE Bent-Knee Push-Up](https://www.acefitness.org/resources/everyone/exercise-library/13/bent-knee-push-up/) |
| incline_pushup | 双掌放在实体 0.40 m 高台，脚尖落地，伸直双腿；下降时前臂位于台面后缘外，避免穿台 | [NASM Incline Push-Up](https://www.nasm.org/resource-center/exercise-library/incline-push-up) |
| floor_press | 仰卧，肩背与双脚稳定落地，屈膝；两哑铃从胸旁向上推举，上臂保留地面净空 | [Nike Floor Press / Bench Press](https://www.nike.com/a/how-and-why-to-do-a-bench-press/)、[Nike dumbbell floor-press instructions](https://www.nike.com/at/en/a/workout-for-beginner) |
| shoulder_press | 站姿双哑铃肩推；躯干与脚稳定，肘部从两侧向上伸展 | [ACE strength workout: Dumbbell Shoulder Press](https://www.acefitness.org/resources/pros/expert-articles/5047/strength-training-workout-for-beginners/) |
| lateral_raise | 站姿双臂向两侧抬至肩部附近，肘部微屈，受控返回 | [ACE lateral raise cues](https://www.acefitness.org/resources/everyone/blog/4847/hiit-upper-body-workout-try-this-fat-blasting-workout/) |
| single_arm_row | 右手单哑铃后拉，左掌在实体 0.45 m 台面上支撑，两脚落地，躯干保持固定 | [ACE single-arm row](https://www.acefitness.org/resources/everyone/exercise-library/126/single-arm-row/)、[NIFS supported one-arm row](https://wellness.nifs.org/hubfs/FM%20Intranet%20Files/AA_Guide_In-Home%20Workout_Book%20Form.pdf) |
| reverse_fly | 站姿髋铰链前倾，微屈肘，两臂向外展开，躯干稳定；不是划船式大幅屈肘 | [ACE reverse-fly hip-hinge variation](https://www.acefitness.org/continuing-education/certified/april-2024/8616/fit-for-two-navigating-third-trimester-training-for-prenatal-clients/)、[Mayo Clinic movement cues](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/reverse-fly/vid-20084679) |
| romanian_deadlift | 双哑铃近身下放，髋后移约 0.235 m，躯干倾角变化约 64°，双膝最小夹角约 148.6°，没有退化成深蹲 | [NASM Dumbbell Romanian Deadlift](https://www.nasm.org/resource-center/exercise-library/dumbbell-romanian-deadlift) |

所有动作沿用 0–0.5 s 准备、0.5–3 s 主动作、3–3.5 s 停留、3.5–5.5 s 返回、5.5–6 s 准备的节奏。卧推、肩推、侧平举、反向飞鸟和划船的主动作方向为推起/抬起/拉起；俯卧撑与 RDL 为下放。单臂划船明确示范右侧，没有在一个循环内换侧。

## 验证

`tools/check_motion_upper.py` 从实际交付 GLB 重新导入，在 361 个时刻（含关键帧中点）检查：

- 动画唯一性、名称、6 秒时长、LINEAR 插值。
- 四肢、脚趾根、锁骨到上臂、脊柱、颈头及每条手指链的连续性与骨长。
- 全部人体蒙皮顶点的最低高度、脚掌/手掌/膝前/肩背的真实支撑皮肤高度。
- 支撑骨锚点与蒙皮支撑见证点的漂移；膝前滚动允许关节高度随皮肤包络变化，仍严格检查水平滑移和地面间隙。掌心见证点排除参与手腕变形的前臂混合权重点；腕缘仍包含在整体穿地和接触高度检查内。
- 台面实际包围体与人体穿插、掌心是否落在台面范围内。
- 骨骼与蒙皮的循环闭合、哑铃在手骨局部坐标中的刚性附着、每个动作的最低运动幅度、上斜膝伸直与 RDL 髋铰链角度。
- 全循环模型及道具的世界坐标包围范围，供应用相机取景使用。

阈值保持关节间隙 < 0.5 mm、支撑滑移 < 0.6 mm、循环间隙 < 0.6 mm、骨长误差 < 0.2%、皮肤不低于地面 -1 mm、支撑皮肤不高于对应支撑面 6 mm、器械附着误差 < 0.5 mm。没有通过放宽阈值掩盖失败。

完整结果：`.build/motion-library/upper-all-verification.json`。实际数值的紧凑统计见本报告末尾。所有 8 个动作最终 `errors` 为空。

## 失败驱动的修正证据

`upper-evidence/missing-before-authoring.log` 保存了编写动作前缺失 GLB 的失败。`upper-evidence/candidate-failures.json` 记录了候选版本的失败与修正：

1. 跪姿最低处隐藏皮肤碰地，窄膝部采样遗漏了上侧髌骨；扩展膝前采样范围，通过逐帧真实表面求解保持接触，再固定小腿朝向消除不必要扭转。
2. 卧推逐帧背部校准造成约 3.5 mm 躯干漂移；改成准备姿势只校准一次，整个推举期间躯干固定。
3. 单臂划船最初的支撑点超过手臂总长；重新匹配髋高与掌心位置，没有缩放骨骼。
4. 扩展检查揭示上斜前臂穿台约 12.2 mm、划船小腿穿台约 68.1 mm；通过移动平台后缘和缩短划船支撑台消除。

负向控制使用上斜 GLB：人为添加 20 mm 根部水平滑动，`skin support drift` 和 `support drift` 均失败；人为添加 20 mm 手腕断开，`joint gap`、皮肤与骨锚点漂移检查均失败。数据保存在 `upper-incline_pushup-negative-drift.json`、`upper-incline_pushup-negative-gap.json`，对应日志在 `upper-evidence/negative-*.log`。

## 复现

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python tools/motion_library.py -- --exercise incline_pushup --render
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python tools/check_motion_upper.py
# 验证指定发布资产（同一动作）：
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python tools/check_motion_upper.py -- --exercise incline_pushup --glb /absolute/path/athlete_incline_pushup.glb
```

本模块未改动原 8 个动作、原始人体源文件、Flutter 或肌肉覆盖层。道具节点命名为 `PULSE support top` / `PULSE support leg …` 与 `PULSE dumbbell l/r`，便于编辑和排查。

## 最终数值摘要

单位为毫米；接触范围相对于对应地面或台面。每个动作采样 361 次。

| 动作 | 最大关节间隙 | 最大支撑蒙皮漂移 | 最低人体皮肤高度 | 最大哑铃附着误差 | 蒙皮循环间隙 |
|---|---:|---:|---:|---:|---:|
| kneeling_pushup | 0.0005 | 0.0301 | 0.9985 | 0.0000 | 0.0005 |
| incline_pushup | 0.0004 | 0.0266 | 0.9988 | 0.0000 | 0.0004 |
| floor_press | 0.0003 | 0.0004 | 0.9671 | 0.0003 | 0.0004 |
| shoulder_press | 0.0006 | 0.0003 | 0.0605 | 0.0006 | 0.0007 |
| lateral_raise | 0.0005 | 0.0003 | 0.0605 | 0.0005 | 0.0009 |
| single_arm_row | 0.0004 | 0.0004 | 0.0604 | 0.0002 | 0.0005 |
| reverse_fly | 0.0004 | 0.0005 | 0.0605 | 0.0003 | 0.0007 |
| romanian_deadlift | 0.0005 | 0.0291 | 0.0494 | 0.0003 | 0.0007 |
