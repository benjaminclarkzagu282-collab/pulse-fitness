# iPhone device acceptance

本机软件验证与真正 iPhone 验收分开。执行 `python3 tools/check_ios_readiness.py` 读取环境；没有完整 Xcode 时不能生成或宣称已验证的手机安装包。

## 配置与安装

按 [Flutter iOS 官方配置](https://docs.flutter.dev/platform-integration/ios/setup) 安装完整 Xcode 与 iOS 平台支持。连接、解锁并信任 iPhone，按系统提示开启开发者模式。打开 `ios/Runner.xcworkspace`，使用自己的 Apple 账号选择签名团队，确认唯一 Bundle ID。

普通个人账号可以真机测试，付费会员及发布是独立步骤。此项目当前不自动替用户购买、发布或接受新协议。

原始 24 模型位于 `assets/models`，其中深蹲/俯卧撑随安装包内置；全部压缩交付文件位于 `web/remote/models`。其余模型要求部署这些静态文件并配置实际资源主机；视频全部内置作为离线示范。

```sh
/Users/jiyibo/.local/share/flutter/bin/flutter run -d <真实设备ID> --release --dart-define=PULSE_ASSET_BASE_URL=https://<实际资源域名>/
```

生产使用 HTTPS；跨域资源主机须允许 App 网页来源的 CORS 请求。gzip 文件应作为原始二进制下载，不要额外设置 `Content-Encoding: gzip`，避免透明解压导致校验不符。尚未配置主机的原生版本会明确提示并提供内置视频，不会猜测 localhost。

## 必须记录的真实结果

记录 iPhone 型号、iOS 版本、App 构建号、安装日期、资源主机和操作录像。

- 冷启动：断网时基础动作和全部备用视频可用；联网下载显示真实字节/进度。
- 24 动作：逐个播放、暂停、观察关键阶段、正侧背面相机，记录加载时间及失败情况。
- 最大动作：连续切换死虫式、鸟狗式、开合步各 10 次，记录内存、发热、崩溃与丢失画面。
- 生命周期：训练/组间休息时锁屏和切后台，回来仍暂停；明确继续后再计时；不能重复完成组。
- 网络：下载中断、网络切换、缓存再次播放、清理缓存后的重新下载。
- 数据：实际次数/秒数与训练耗时分别记录；自定义食物按克计算；历史摄入不随食物编辑改变。
- 备份：导出到文件，预览后恢复，损坏文件拒绝导入并保留原记录。正式清空只在测试账号/测试安装执行。
- 可访问性：390px 和较小设备、系统大字体、减少动态效果、VoiceOver、键盘及安全区。

每项结果填写通过/失败及证据。上述列表未实测前，`device_acceptance_completed` 必须保持 false。
