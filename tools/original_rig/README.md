# 原始 CAT 绑定接入

2026-09-29 已从 Windows 虚拟机的 3ds Max 2027.2 导出原始 MentalRay MAX，并成功导入 Blender。肩推和弯举的原绑定样板已接入本地对照页：http://127.0.0.1:8879/native-rig-review.html 。主 App 的 24 个动作尚未整体替换。

## 已确认的数据

- 身体 Man：14,260 个顶点，81 根骨骼，最多 8 项权重。逐顶点、逐骨骼权重与 Max 原始审计完全一致，最大差为 0。重名节点按 Bone ID 分别核对。
- 原 Max 与 Blender 参考姿势的身体网格最大位置差约 0.0021 毫米。短裤仍有最大 0.614 毫米差异，未宣称短裤完全保真。
- 原模型 enableDQ=true，但身体、短裤全部顶点的 DQ 混合权重均为 0。原参考变形实际使用线性蒙皮。
- 原 MAX 文件 SHA-256 未变化。FBX SHA-256 为 21c00e94ff4df4461c94f3ee92294aebc55f75a67a874404ee060bc0b79e9d42。
- 原始 CAT 长度轴为 X，导入后的 Blender 显示尾端沿 Y。动作计算使用真实关节原点和原矩阵轴；不拿显示尾端当解剖方向。

## 动作与网页

肩推、弯举使用原绑定驱动，保留每侧三段前臂及原始手指权重。五指姿势按原模型手型与 28 毫米握杆重新拟合。可编辑 Blender 源文件含 81 根骨骼及完整 6 秒动作动画。

当前 model-viewer 的播放器只读取 JOINTS_0 / WEIGHTS_0。为避免丢失第 5–8 项权重，对照页采用从完整原蒙皮求得的网格动画；网页 GLB 因此没有 Skin 骨架。原始 FBX 和可编辑 Blender 源文件仍保存原骨架和全部权重。这是固定示范动画的兼容交付方案，不能当成网页原生 8 权重骨骼播放器。

技术验证：每个动作检查 10 个时间点，手部顶点、三角形中心和边中点抽样均未检出握杆、配重片穿插。GLB 重新导入后，身体和哑铃相对源蒙皮动画的最大误差低于 0.104 毫米。肌群表面图层同步动画；颜色不是实测肌肉受力。动作尚未经教练复核。

## 重建与校验

在 pulse_fitness 项目目录运行：

```sh
'/Applications/Blender.app/Contents/MacOS/Blender' --background --factory-startup --disable-autoexec --python-exit-code 1 --python tools/original_rig/build_native_review.py -- --output-dir .build/original-rig/NEW_OUTPUT
'/Applications/Blender.app/Contents/MacOS/Blender' --background --factory-startup --disable-autoexec --python-exit-code 1 --python tools/original_rig/verify_native_review.py -- --input-dir .build/original-rig/NEW_OUTPUT
python3 tools/original_rig/package_native_review.py --input-dir .build/original-rig/NEW_OUTPUT
python3 -m unittest discover -s tools/original_rig -p 'test_*.py'
```

输出目录须为新目录。构建依赖已经通过检查的 `.build/original-rig/native-import-04/original-rig-staging.blend`。打包仅接受验证通过的样板；摄像机目标从 Blender Z-up 转为 glTF Y-up，避免肩部特写错误对准腿部。

## 原生导出与留档

`export_from_max.py` 在 Max 内运行，读取 CAT / Skin / Morpher，核验 FBX 参数读回值，导出到新的时间戳目录，不保存原 MAX。Skin Bone ID 采用原始连续 ID；保留重名骨骼数量。原生审计与成功 FBX 在 `characters/08_原始骨架接入/incoming/native-export-04/`；原始静态 Man.FBX 没有骨架，不能替代它。

兼容差异已在 Max 2027.2 验证：Skin 排序列表可能为空；FBX 设置返回 True，轴向参数读回为小写 y。临时虚拟机传输服务已关闭，8879 本地预览服务继续供用户使用。

## 待完成

其余 22 个动作迁移、短裤参考差异处理、动作专业复核及主 App 的整体集成。结构与数值验证不等同于训练动作已经获得专业认可。
