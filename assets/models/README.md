# PULSE 写实人物动作资源

当前文件来自用户提供的男性人物网格和贴图，经 Blender 恢复材质、优化、重新绑定和适配动作。它们不是原始几何人偶，也不声明用户素材为 CC0。来源及输入哈希见 `docs/assets/character-sources.json`；升级与验证记录见 `docs/reports/realistic-character-upgrade.md`。

八个 `athlete_<id>.glb` 各包含一个 4 秒的 `Exercise` 循环、53 根骨骼、完整蒙皮和内嵌贴图。动作包括 squat、pushup、lunge、bridge、plank、row、jumping_jack、curl。划船和弯举含项目原有哑铃。glTF 为 Y 轴向上、正面朝 +Z。

每个模型约 6.6 MiB；人物 61,515 个三角面，带哑铃为 61,779 个。身体与头部颜色贴图 2048 像素，法线 1024，其他贴图 512/1024。`validation.json` 保存最终输出哈希、文件大小、循环及蒙皮检查。

动画属于程序生成的动作示意，没有动作捕捉或专业动作校验。结构检查与浏览器观察不等同于真机帧率测试。

可编辑成品在项目旁的 `characters/02_健身人物成品/健身人物_材质骨骼与八种动作.blend`；原始素材保持不变。
