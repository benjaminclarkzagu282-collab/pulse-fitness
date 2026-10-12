# 肘肩变形修复样板

本次修正哑铃弯举与哑铃肩推的肘肩皮肤变形，已更新 `motion-quality-review.html`。页面默认显示修复版弯举的肘部特写，可在同一时间点切换“修复前”，也可查看肩部、握姿、全身及肌群示意。深蹲保持上一版，App 的 24 个动作模型没有被本次样板覆盖。

## 修改内容

- 前臂增加渐进旋转控制，重分配肘部过渡权重；保留原有手掌、五指、哑铃位置与动作轨迹。
- 用九个姿势校正形态补偿肘肩塌陷，肘窝局部平滑，限制修正范围，避免牵动下方躯干。最终采用标准 GLB 骨骼和 morph 动画。
- 按实际变形后表面烘焙法线，避免直接在逆变形网格上生成法线导致的假接缝。每个形态同时含位置和法线；浏览器实际渲染已检查。
- 肌群层复制相同形态、动画与蒙皮，颜色层随皮肤共同变化。

## 检查结果与证据

每个动作在完整六秒循环中采样 361 个时间点。双侧弯举肘部跟踪截面的最小面积比从约 **0.208** 提高至 **0.807**（以绑定姿态同一圈皮肤为基准）。肩推肩外侧补片的最小方向伸长率第十百分位从约 **0.157** 提高至 **0.329**。这些是用于识别塌陷的工程指标，不是肌肉体积、肌力或人体生理指标。

肩肘局部自相交检查在 15 个选定帧中未检出超过 1 mm 的非共面交线。该检查不覆盖任意连续时刻、全身、共面重叠与亚毫米接触，不能据此声称全身绝对无穿插。

最终发布的两份 GLB 还分别通过：

- 361 点握持与器械间距检查：手和握把的最小表面间距约 0.203 mm，最大手指接触间隙约 0.717 mm；没有失败样本。
- 361 点动作检查：骨骼长度、关节连续性、手腕方向、脚底和首尾循环均通过；肩推肩带仍随上举移动。
- 181 帧肌群贴合检查：最大表面偏移约 0.8003 mm，符合原定 0.8 mm 叠层偏移；肌群层与身体的形态动画权重一致。
- 导出回归：9 个形态实际驱动皮肤，形态权重随动作变化，首尾一致。
- 8 项共享肌群控制器测试；桌面和 390 px 手机视口下的切换、慢放、逐帧、特写、肌群显示检查；本次页面运行错误日志为空。
- 独立只读代码复核及最终 GLB 结构检查，未发现阻断交付的问题。

几何检查使用 `.build/joint-volume/{exercise}/base.glb`；`tools/verify_joint_volume_delivery.py` 精确比较了最终发布版本与 base 的原网格属性、索引、骨骼绑定、动作及所有位置/法线形态，确认包装没有改变受测内容。发布 SHA、尺寸与结果在 [joint-volume-delivery.json](joint-volume-delivery.json)，原始检查记录在 [joint-volume-evidence](joint-volume-evidence)。握持、动作和贴合报告直接使用最终发布 GLB。

截图：[肘部修复前](joint-elbow-before.png)、[肘部修复后](joint-elbow-after.png)、[肩部修复前](joint-shoulder-before.png)、[肩部修复后](joint-shoulder-after.png)、[肌群显示](joint-shoulder-muscles.png)、[手机逐帧操作](joint-mobile-controls.png)。

## 文件与复现

- 新样板：`web/review/quality-v2/{curl,shoulder_press}.glb`，同步到 `build/web/review/quality-v2`。
- 修复前样板仍为 `web/review/quality`，没有覆盖。
- 已打包贴图的可编辑文件与独立 GLB：`/Users/jiyibo/Desktop/建模游戏/characters/07_肘肩变形修正`。
- 工具版本：Blender **5.2.1 LTS**。
- 原始人物资产：`/Users/jiyibo/Desktop/建模游戏/pulse_fitness/.build/realistic-character/athlete-source.blend`。
- 原始文件 SHA-256：`f94a16296fdcade19edc509df33b25993341e4021bc7f245c1b820942f4ddd83`。

原始人物和 `.build` 工作文件不在 Git 中；干净检出必须先恢复该资产，不能仅凭新脚本生成原始人物。复现时在项目目录依次执行：

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python tools/build_joint_volume.py -- --exercise curl
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python tools/build_joint_volume.py -- --exercise shoulder_press
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python tools/package_joint_volume.py
python3 tools/verify_joint_volume_delivery.py
```

另外运行 `check_joint_volume.py`、`check_joint_volume_export.py`、`check_quality_upper.py`、`check_quality_equipment.py` 和 `check_joint_volume_layers.py`；参数示例见各文件。GLB 的姿势法线由导出流程烘焙，直接从 Blender 手动重新导出会丢失这一步。Blender 重新导入 GLB 后的灰模显示也不等同于浏览器对动画法线的渲染。

本次交付是针对两个既有动作的变形修复样板，不是完整解剖肌肉模拟；动作教学仍待教练复核。
