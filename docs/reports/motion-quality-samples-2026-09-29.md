# 三项动作校正样板

本批完成深蹲、哑铃弯举和哑铃肩推的独立候选，保留原人物外形。预览地址：http://127.0.0.1:8879/motion-quality-review.html 。原 24 项正式资产未被本批替换，验收通过后再推广。

## 改动

- 深蹲重新标定腿部屈曲平面和骨骼轴向，膝盖运动方向与脚部方向协调，手臂随下蹲/起身同步。候选底部屈膝约 90.99°，原版约 117.81°；本次采用较浅示范，不是通用深度限制。
- 弯举保持上臂位置，重新建立前臂/手掌参考坐标，校正腕部扭转，并逐指设定围握。
- 肩推补入锁骨与肩带随上举移动，手臂在略偏前方的平面内运动，保持手掌与前臂协调。源角色没有独立肩胛骨控制器，这里是现有肩带骨骼的近似，不能视为完整肩胛胸廓仿真。
- 哑铃重新建立握持坐标，手指独立弯曲、拇指对握，采用手骨蒙皮固定器材。实际动画已烘焙入 GLB，浏览器播放时不另行驱动哑铃或关节。
- 肌群示意最后附加；验证其未改变候选动画、原网格顶点、权重或骨骼绑定。

这些候选由可编辑关键姿态和插值制作，并非真人动捕。没有使用收费素材或新增人物模型。

## 证据

最终带肌群 GLB 经独立回读检查，各采样 361 个时刻，含 30 fps 动画的半帧。

| 项目 | 原版 | 候选 |
| --- | --- | --- |
| 深蹲膝盖运动平面/脚部方向最大差 | 36.81° | 约 0° |
| 深蹲膝前皮肤方向偏差（选定表面标记点） | 30.65° | 10.54° |
| 弯举、肩推手掌轴/前臂最大夹角 | 11.54° | 约 0° |
| 肩推肩部垂直行程 | 0 mm | 27.10 mm |
| 肩推锁骨旋转变化 | 0° | 10.20° |

弯举和肩推均通过手部与哑铃、非握持身体与哑铃检查：每个采样时刻左右各检测一次；有限圆柱与真实蒙皮三角面裁剪检查未报告相交，且检查器可发现器材完全埋入身体的负例。握把的最小采样表面净空约 0.203 mm，五指最大接触间隙约 0.717 mm；静态逐三角检查的最小净空约 0.190 mm。非握持身体到器材的最小采样净空：弯举 22.16 mm、肩推 42.69 mm。这些是本模型、器材和采样精度下的工程结果，不是对任何速度/比例变化的绝对保证。

深蹲最大脚漂移 0.128 mm，关节端点误差 0.167 mm；循环、骨长、脚底接触和连续性检查均通过。故意扭小腿和滑脚的负例会失败。原人物几何、权重、材质分配保持一致。

报告：

- `quality-delivery-verification.json`：最终 GLB 的 SHA-256、尺寸及肌群绑定验证。
- `.build/motion-quality/squat/candidate-verification.json`：深蹲采样结果。
- `.build/motion-quality/{curl,shoulder_press}/verification.json`：上肢骨骼、脚底、循环及轨迹结果。
- `.build/motion-quality/{curl,shoulder_press}/equipment-verification.json`：最终 GLB 全程握持/身体与器材检查及 SHA-256。
- `.build/motion-quality/grip/`：新旧握姿、GLB 往返和故意穿入躯干的负对照证据。

浏览器验证：三项切换、新旧版本保留时间、正侧背预设、握姿跟随、0.25 倍慢放、前后逐帧、暂停/定位、肌群开关及自由视角保留；手机有效视口宽 375 px 下肩推起始/峰值头脚和哑铃均完整，没有横向溢出。深蹲新版 3.40 秒显示起身，旧版仍显示底部停顿，与各自动画匹配。复用肌群控制器 8 项测试通过，Python 和页面脚本语法检查通过。

关键画面：`quality-grip-browser.png`、`quality-mobile-press.png`、`quality-squat-browser.png`。

## 交付和复现

可编辑文件已整理到 `/Users/jiyibo/Desktop/建模游戏/characters/06_动作校正样板`。每个动作有普通 Blender 源文件、带肌群的 Blender 源文件、网页 GLB 和对应验证结果。源文件与工作区生成物逐文件哈希一致。

脚本：`quality_squat.py`、`quality_upper.py`、`quality_grip.py` 定义姿态；`build_quality_samples.py` 烘焙；`package_quality_samples.py` 添加肌群并打包；`verify_quality_delivery.py` 检查包装过程；`check_quality_equipment.py` 检查最终器材接触。

在项目目录中，用 Blender 运行 `tools/build_quality_samples.py -- --exercise squat`，将 exercise 换成 curl、shoulder_press 可重建其余两项；再用 Blender 运行 `tools/package_quality_samples.py`。`web/motion-quality-review.html` 同步到 `build/web/motion-quality-review.html`；使用 Python 执行 `tools/verify_quality_delivery.py`。原人物基础文件仍依赖 `.build/realistic-character/athlete-source.blend`，复制交付源文件本身可以直接编辑，但不要误称整套生成流程已打包成独立工具。

## 参考与验收边界

- [ACE 深蹲](https://www.acefitness.org/resources/everyone/exercise-library/135/bodyweight-squat/)
- [Mayo Clinic 深蹲示范](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/squat/vid-20084663)
- [Mayo Clinic 弯举示范](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/biceps-curl/vid-20084675)
- [ACE 初学者力量训练示范（含肩推）](https://www.acefitness.org/resources/pros/expert-articles/5047/strength-training-workout-for-beginners/)

参考用于确定定性动作方向；本角色的具体角度和时间是人工制作参数，未从视频提取动捕，未作个体化力学求解。工程通过不等于教学动作认证。最终自然度、深蹲幅度及示范准确性仍需人工与专业教练复核。肌群颜色仅表示参与角色和阶段，不代表实测肌肉力、肌电或运动安全评分。
