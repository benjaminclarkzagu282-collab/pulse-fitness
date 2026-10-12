# 八动作基础动画库

2026-09-28。基于用户提供的写实人物和既有 53 骨骼绑定，在本地 Blender 5.2.1 制作；无付费动作 API、无动作捕捉声明。保留既有正常人物网格，划船和弯举包含双哑铃。肌肉表面覆盖层由后续流水线另行添加。

## 动作与节奏

所有资产仅含一个名为 `Exercise` 的 6 秒动画，30 fps、0–180 帧逐帧烘焙；源动作与导出 GLB 均为 LINEAR。禁用导出器的关键帧简化，以保留完整的保持段。

| ID | 实际编排 |
| --- | --- |
| squat | 原样调用用户已认可的 `squat_sample.pose_squat`，不重新解释姿势 |
| pushup | 掌部和脚趾保持支撑，连贯躯干下降、上推 |
| lunge | 左脚支撑、右脚后退并收回的单侧反向弓步；不是左右交替 |
| bridge | 双脚、双掌固定，上背保持地面接触；髋部上抬，颈部和头部连接完整 |
| plank | 连续静态前臂支撑；肩在肘上，按真实前臂长放置手腕 |
| row | 固定髋铰链与腿部支撑，双臂提拉哑铃、控制放回 |
| jumping_jack | 合拢与张开之间有独立腾空段，只有腾空时改变脚部横向位置，落地时缓冲屈膝 |
| curl | 躯干与上臂稳定，双前臂带动哑铃弯举、控制放回 |

除平板和开合跳外，一般节奏为 0–0.5 秒准备、0.5–3 秒控制移动、3–3.5 秒停留、3.5–5.5 秒返回、5.5–6 秒恢复。反向弓步细分为 0.5–1 秒退步、1–3 秒下蹲、3–3.5 秒停留、3.5–5 秒上起、5–5.5 秒收步。开合跳在 0.8–1.4 秒跳开、3.8–4.4 秒跳回，其余阶段准备、落地缓冲或保持。这是放慢的观察循环，不是建议训练速度。

## 参考与取舍

- 深蹲沿用已认可样板及其 [ACE 参考](https://www.acefitness.org/resources/everyone/exercise-library/135/bodyweight-squat/)。
- [NASM Push-Up](https://www.nasm.org/resource-center/exercise-library/push-up)：连贯躯干、略宽于肩的掌部支撑、控制下降和推起。
- [NASM Reverse Lunges](https://www.nasm.org/resource-center/blog/squat-alternatives)：后退迈步、前腿承重。此处按人物骨长重新编排单侧步幅。
- [ACE Glute Bridge](https://www.acefitness.org/resources/everyone/exercise-library/49/glute-bridge/)：屈膝、双脚支撑、髋伸展与控制下降。上背接触是蒙皮表面滚动接触，不把头骨任意平移到独立目标位置。
- [ACE Front Plank](https://www.acefitness.org/resources/everyone/exercise-library/32/front-plank/)：肘靠近身体且位于肩下，躯干与腿保持稳定。
- [ACE Bent-over Row 研究动作描述](https://contentcdn.eacefitness.com/April2018/ACE_BackExerStudy.pdf)：髋部前倾、轻屈膝、稳定背部并屈肘提拉；此资产使用双哑铃版本，不声称复刻研究中的杠铃试验。
- [ACE Biceps Curl](https://www.acefitness.org/resources/everyone/exercise-library/44/seated-biceps-curl/)：控制屈肘、保持手腕和上臂稳定。本资产采用站姿；引用的是手臂动作要点，不是坐姿动作的完整复刻。
- [NASM Jumping Jacks](https://www.nasm.org/workout-exercise-guidance/how-to-jumping-jacks)：屈膝起跳、四肢协调张开、轻柔落地。

这些是按参考重新编排的视觉样板，并非专业教练或医疗认证。具体角度、步幅和时长是这副模型的制作参数；没有测量或推断真实肌肉激活强度。保留原人物与贴图授权，不因动画改动而改变素材许可。

## 修复与证据

旧两段关节求解器在目标超出骨长时仅截短计算距离，却仍把下一节骨骼放到未截短的端点，导致关节断开。新求解器对不可达目标直接报错，由动作编排保证目标可达；其它动作直接从骨长推导端点。

掌部朝向采用腕部到掌指关节的平面，手指和拇指逐节展开，避免用中指尖方向代表掌面。掌心检查只选择 `hand_*` 权重占比超过 0.7 的皮肤顶点；不再以指尖或拇指的最低点替代掌心接触。平板也独立检查肘附近区域。

每个最终 GLB 重新导入 Blender，检查 361 个时间点（30 fps 每帧及半帧），包括世界坐标支撑漂移、肢段及指节连接、所有骨长、循环闭合、全身蒙皮最低高度、掌心/脚底/肘/上背接触，以及各动作应有的运动幅度。平板明确要求保持稳定，防止为“有动画”而添加虚假晃动。

可复现的失败用例：

1. 旧版平板断腕：39.639 mm，`--legacy --exercise plank` 检查失败。
2. 早期修复中拇指贴地但掌心悬空：独立掌心判据捕获 25.477 mm 的离地，记录在 `palm-red-test.log`，随后修复。
3. 人工令整个角色中途横移 20 mm：世界坐标支撑检查失败，证明未只测局部骨骼坐标。
4. 人工将手腕与前臂分离 20 mm：关节连接检查失败。

地面容差为 1 mm，固定支撑漂移容差为 0.6 mm；这些是导出插值与蒙皮的几何容差。全身碰撞、手指之间碰撞和人体生物力学不是本检查器的认证范围。另以本地离线渲染查看全部八动作的准备/主要姿态；未调用浏览器。

## 文件与复现

- 制作脚本：`tools/motion_library.py`
- 检查脚本：`tools/check_motion_library.py`
- 逐动作编辑源：`.build/motion-library/<id>.blend`
- 正常网格 GLB：`.build/motion-library/base/<id>.glb`
- 几何报告：`.build/motion-library/verification.json`
- 结构报告：`.build/motion-library/structure.json`
- 离线渲染：`.build/motion-library/renders/`
- 负例和构建日志：`.build/motion-library/`

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python tools/motion_library.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python tools/check_motion_library.py
```

制作命令可追加 `-- --exercise pushup` 单独输出一个动作，或追加 `-- --render` 生成三阶段渲染。检查命令可追加 `-- --exercise plank --inject-root-slide` 或 `-- --exercise curl --inject-joint-gap` 运行应失败的负例。

既有 `finalize_character_assets.validate(..., texture_limit=2048, duration=6)` 对七个动态动作通过有限数值、归一化权重、53 骨骼、内嵌纹理和闭环检查。它强制至少一个动态通道，因此不用于有意静态保持的平板；平板由新检查器验证完整时长、LINEAR 轨道、骨骼、皮肤与稳定性。

## 最终数值

单位为毫米；骨长误差是所有骨骼的最大相对误差。

| 动作 | 最大连接差 | 固定支撑漂移 | 最低皮肤高度 | 接触区最高最低点 |
| --- | ---: | ---: | ---: | ---: |
| squat | 0.0005 | 0.1014 | -0.0234 | 0.0617 |
| pushup | 0.0004 | 0.0276 | 0.9997 | 1.4759 |
| lunge | 0.0004 | 0.4300 | -0.3665 | 0.0607 |
| bridge | 0.0005 | 0.0082 | 0.9966 | 1.9186 |
| plank | 0.0003 | 0.0001 | 1.0001 | 2.4167 |
| row | 0.0004 | 0.0001 | 0.0607 | 0.0619 |
| jumping_jack | 0.0008 | 0.0000 | -0.4718 | 腾空分段检测 |
| curl | 0.0004 | 0.0002 | 0.0605 | 0.0616 |

全库最大相对骨长误差 0.000473%；最大首尾位置差 0.000564 mm。开合跳地面相邻采样最大脚部横向变化 0.1242 mm，腾空脚高度变化 95.532 mm；反向弓步后脚前后行程 500.018 mm。


## 臀桥峰值的二次复核

最终侧面审看提示抬髋偏高，随后测量发现原峰值肩—髋—膝的侧面夹角为 161.646°，髋骨点高出肩—膝侧面连线 67.083 mm。先在检查器中加入“髋部高出该连线不得超过 15 mm”的模型视觉回归，确认旧资产失败，再把臀桥新增旋转幅度从 0.50 rad 降到 0.354 rad；其他七个模型的 SHA-256 未变。

修正后左右峰值侧面夹角均为 179.944°，髋部位于该连线下方约 0.201 mm，抬髋行程仍为 131.620 mm。原始三维夹角为 159.024°、三维点线距离约 70.411 mm，其中包含肩宽到髋宽的横向差，不能直接解释为矢状面的腰部过伸。该门槛是针对本模型的明显拱腰检查，不是对真实人的标准角度要求。

新臀桥实际 GLB 的 361 点检查通过：上背接触高度为 0.997–1.047 mm，固定支撑最大漂移为 0.0083 mm。单独重导了 `bridge.glb` 与 `bridge.blend`，并更新离线峰值渲染、结构报告和哈希清单。旧姿态应失败日志保存在 `.build/motion-library/bridge-overextension-red.log`。
