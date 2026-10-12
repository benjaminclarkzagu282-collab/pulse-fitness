# 写实健身人物升级结果

完成日期：2026-09-28。采用用户提供的 `3D model Realistic Rigged Man Vray & MentalRay` 本地素材。

## 已交付

- 恢复身体、头部、眼球、虹膜、口腔及内裤的材质，使用原包颜色和法线贴图。
- 将原模型的身体、头部两块 UV 区域转换为独立材质；重建丢失的眉毛毛发效果。
- 精简眼部与口腔细节，人物从 163,710 个三角面降低为 61,515 个；带哑铃动作 61,779 个。
- 为新体型拟合 53 根骨骼，重新生成蒙皮，每顶点至多 4 个归一化权重。修正脚底受到小腿骨骼牵拉、弓步脚尖穿地、臀桥手臂穿地以及俯卧撑/平板脚尖悬空的问题。
- 适配深蹲、俯卧撑、反向弓步、臀桥、平板支撑、哑铃划船、开合跳、哑铃弯举 8 种循环。
- 替换首页人物、8 张动作缩略图、主图、头像共 11 张图片，替换 8 个实时 GLB。原有旋转、暂停、慢放、正面/侧面控制保持兼容。
- 保存可编辑 Blender 成品：`../characters/02_健身人物成品/健身人物_材质骨骼与八种动作.blend`。包含内嵌贴图、骨骼、8 个动作和可选哑铃集合。

## 数据与加载

每个 GLB 为独立完整文件，约 6.6 MiB，全部 8 个合计约 53.0 MiB。身体、头部颜色贴图为 2048 像素，法线为 1024，其他贴图为 512/1024。人物的几何复杂度下降，但为保留皮肤细节，文件比上一版 1024 像素贴图人物更大。各动作按需加载，没有把 3.5 GiB 原包放入 App。

每个文件只有一个名为 `Exercise` 的 4 秒动画。源文件保留 8 个分别命名的动作。坐标保持 Blender Z 向上、面朝 -Y，导出后 glTF Y 向上、面朝 +Z。

## 验证证据

1. `tools/verify_realistic_character.py` 对真实 Blender 源文件验证：骨骼存在、每个可见网格已蒙皮、UV/材质存在、贴图可用且不超过 2048、权重归一化且不超过 4 个、三角面数量低于 65,000。8 种动作在 0、25%、50%、75%、100% 时刻检查有限坐标、闭环和地面穿透；俯卧撑、平板支撑额外检查脚尖不过度悬空。最终通过。
2. 初始原文件因无骨骼未通过；初次脚底校正前的弓步被接地检查拦截。修正后通过，证明检查覆盖了实际缺陷。
3. 最终全部 8 个 GLB 通过结构验证：单个皮肤、53 关节、4 秒闭合动画、时间戳严格递增、实际变化通道、有限数值、归一化权重、内嵌贴图，无渲染灯光/相机。结果及 SHA-256 位于 `assets/models/validation.json`。
4. 11 张 PNG 均有非空透明背景；完整人物缩略图/首页图轮廓留有边距，头像允许肩部裁切。
5. `dart analyze`：无问题。`flutter test`：55 项通过。`flutter build web --release`：成功。
6. 实际浏览器检查首页、动作库和站立/地面动作。验证模型加载、暂停、正侧面切换与 0.5 倍速控件；390×844 的手机宽度预览中，俯卧撑模型与按钮完整可见。
7. 独立审查验证了最终资源结构、编辑源的 8 个动作和查看器兼容性；未发现 Critical 或 Important 问题。提出的哑铃源文件缺失及脚尖悬空问题已处理。
8. 本轮使用的原素材哈希均与检查前清单相同；最终 8 个 GLB 在资源目录、验证记录和网页构建目录中一致。

实际画面：

- [桌面首页](realistic-desktop-home.png)
- [手机首页](realistic-mobile-home.png)
- [手机俯卧撑](realistic-mobile-pushup.png)

## 可编辑文件与复现

成品中的动作：`squat`、`pushup`、`lunge`、`bridge`、`plank`、`row`、`jumping_jack`、`curl`。每个动作 0–96 帧、24 fps。默认显示深蹲。哑铃位于 `Dumbbells - enable for row or curl` 集合，默认隐藏；在 Blender 查看划船或弯举时同时开启该集合的视图和渲染开关。App 中对应动作已经带哑铃，无需手动设置。

制作脚本依次为：

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --disable-autoexec --python-exit-code 1 --python tools/build_realistic_athlete.py
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --disable-autoexec --python-exit-code 1 --python tools/verify_realistic_character.py -- .build/realistic-character/athlete-source.blend
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --disable-autoexec --python-exit-code 1 --python tools/export_realistic_athlete.py
python3 tools/install_realistic_assets.py
flutter build web --release
```

原始素材保持不变，旧版 App 人物资源另存于 `.build/realistic-character/previous-assets`，也保留在 Git 历史。没有改动训练计划、饮食、评分及用户记录逻辑。

## 实际限制与来源

动作是程序驱动的示意动画，没有专业动作捕捉或动作医学验证；弓步重复同一侧。采样检查不能证明所有角度和插值时刻完全没有轻微形变/衣物交叠。页面在本机浏览器验证，尚未进行 Android/iOS 真机安装或帧率测试。

用户提供的人物网格和贴图没有附带授权说明，本项目未把它们标记为 CC0。来源及原文件哈希见 `docs/assets/character-sources.json`。沿用并拟合的 MakeHuman 骨架来源另存于 `character-sources-makehuman.json`；旧 CC0 文件仅针对相应历史素材与骨架。
