# PULSE · 动起来

本地优先的 Flutter 健身应用：自定义训练计划、参考训练方案、24 种 3D 动作示意、逐组实际训练记录、恢复反馈、按克数记录食物、每日完成度及可解释的次日建议。成长页提供体重/腰围趋势和真实记录里程碑，设置页提供手动备份、恢复与隐私说明。

## 运行

Flutter 3.47.5 / Dart 3.13.4。当前机器 SDK 在 `/Users/jiyibo/.local/share/flutter`。

```sh
export PATH="$HOME/.local/share/flutter/bin:$PATH"
flutter pub get
flutter run -d chrome
```

或构建静态预览：

```sh
flutter build web --release
python3 -m http.server 8879 --bind 127.0.0.1 --directory build/web
```

打开 http://127.0.0.1:8879 。不要通过 file:// 打开；本地模型需要 HTTP 服务。网页构建会带上 `web/remote/models` 下的压缩资源；首次加载非内置动作需要下载，之后使用通过校验的缓存。

## 已实现

- 今天：原创照片训练主卡、周历、训练入口、饮食与饮水统计；训练方案、身体记录、动作示范、饮食记录快捷入口，以及真实近 7 天概览。
- 计划：目标/器材/时间/日期设置；动作添加、删除、排序；组数、次数、休息编辑。
- 方案：四种可调整的参考训练组合，预览具体动作后安排到今天或明天。已有完成组的当天禁止快捷覆盖；替换已保存的日期计划须确认。
- 动作：24 种动作；关键词、部位、器材、收藏筛选；3D 旋转、缩放、暂停、慢放、正面/侧面/背面和分阶段暂停。教学卡提供要点、常见错误、同类动作与来源；全部明确标记“待教练复核”。
- 资源：深蹲、俯卧撑内置，22 个模型按需下载；显示真实下载进度，校验压缩及解压后的 SHA-256，并提供重试和缓存清理。24 个本地轻量视频用于 3D 加载失败时的示范。
- 跟练：每组可填实际次数或秒数、重量；也可只确认完成，缺失的实际数据保持为空。保留休息计时、替换动作、疲劳反馈，切入后台后暂停，返回需主动继续。
- 饮食：原有四餐、份量、偏好、忌口、饮水和每日营养目标；另可创建注明来源的每 100g 食物，按实际克数记入餐次。已摄入条目保留独立快照，编辑食物库不会改写历史；未来日期只能规划。
- 记录：透明的计划完成度评分；今日/7/30 天历史；睡眠、酸痛及疼痛反馈；训练建议参考相关动作的真实记录和恢复情况，饮食建议比较完整餐食的能量与宏量营养，说明原因并由用户采用。
- 成长：累计实际训练天数、完成组数、已记录跟练时间、饮食记录天数；里程碑从这些记录计算，不存虚构成果。每日体重和腰围可分别填写、编辑、删除，7/30 天测量图不补零或推算缺失日期。
- 设置与数据：导出 JSON 下载/系统分享或复制；粘贴备份后先校验、预览再确认恢复；保留覆盖前的本机备份，写入失败回滚。损坏记录先留存原始内容，再允许恢复。清空记录与删除保留备份各有确认。
- 本地 JSON v6 持久化，日期隔离，重复组完成去重；v1–5 记录可加载与恢复。身体记录独立保存并纳入备份，不改变训练和饮食评分。

## 范围

浏览器版已做本地验证。iOS 工程保留，但本机缺少完整 Xcode 与 CocoaPods，尚未完成 iPhone 安装、帧率、温升、内存及系统分享验收。详见 [iPhone 验收步骤](docs/ios-device-acceptance.md)。原生版本还需配置真实 HTTPS 资源地址：`--dart-define=PULSE_ASSET_BASE_URL=https://实际资源域名/`；未配置时非内置动作会提示使用本地视频。

当前人物采用用户提供资产的原始骨架、蒙皮及原生动画制作链路，网页 GLB 使用烘焙后的网格动画，详见 [原生动作迁移](docs/reports/native-motion-migration.md)。本次资源压缩没有修改模型或动作字节：24 个原始 GLB 共约 689 MiB，压缩传输约 425 MiB，内置模型约 71 MiB；这不是完整 iOS 安装包大小。技术检查不能替代教练逐动作复核，当前全部属于参考示范。肌肉颜色只示意参与程度，不表示测得的受力或肌电数据。

食物营养取决于用户填写或目录注明的来源，按克数估算；摄入目标不是医学处方。评分评估计划记录完成度，不奖励低摄入。建议来自可解释的本地规则，不是已训练的 AI 模型。没有账号、自动云备份、iCloud 同步、HealthKit 或摄像头识别；浏览器清除站点存储可能移除记录和本机备份，请先主动导出。备份 JSON 未加密；资源下载服务可见请求 IP 和路径。详细说明见应用设置页及 [隐私页](web/privacy.html)。

## 验证

```sh
dart analyze
flutter test
flutter build web --release
```

本机 `flutter analyze` 的新 LSP 通道在中文绝对路径上可能抛出截断 JSON 错误；`dart analyze lib test` 能运行同一项目的静态分析。初版记录见 `docs/reports/verification.md`，六项完善见 [交付验证报告](docs/reports/2026-10-03-six-improvements.md)，新界面、训练方案与成长功能见 [改版验证报告](docs/reports/2026-10-03-visual-growth.md)。

## 项目结构

- `lib/core`：领域模型、动作/餐食库、本地状态与推荐规则。
- `lib/screens`：五个导航页和跟练页。
- `lib/ui`：设计系统、3D平台适配与共享组件。
- `assets/models`：模型、验证结果及素材来源说明。
- `tools/original_rig`：原始人物骨架、蒙皮、原生动作及网格动画交付链路；早期重新拟合骨架脚本保留作历史记录。
- `tools/prepare_model_delivery.py`：无损压缩、传输清单及逐文件解压校验。
- `tools/render_fallback_videos.py`：从原生动作源文件渲染本地轻量示范视频。
- `tools/check_ios_readiness.py`：本机 iOS 工具链检测；不等同于真机验收。
- `docs/design-board-*.png`：批准的视觉方向。

字体：Noto Sans SC，SIL Open Font License，见 `assets/fonts/OFL.txt`。餐食图片由内置 imagegen 生成，为搭配示意；原创训练封面的精确提示词与来源见 [生成记录](docs/design/2026-10-03-generated-cover.md)，仅用于页面装饰。当前人物来源见 `docs/assets/character-sources.json`，升级结果见 `docs/reports/realistic-character-upgrade.md`。用户提供的网格和贴图没有附带授权文件，不标为 CC0；历史 MakeHuman 骨架与素材来源保存在 `character-sources-makehuman.json`。
