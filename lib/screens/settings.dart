import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/backup.dart';
import '../core/backup_export.dart';
import '../core/model_assets.dart';
import '../ui/theme.dart';

const privacyText = '''PULSE 将训练计划、完成组数与实际次数/重量、疲劳与恢复反馈、饮水、饮食记录、身体测量与备注、自定义食物、目标、偏好和收藏保存在当前设备或浏览器的本地存储中。当前版本没有账号、云端同步或自动上传个人记录功能；换设备需手动导出并导入。

3D 动作模型按需下载并缓存在设备或浏览器中。请求会发送给当前网站或配置的资源服务器；服务器可能收到 IP 地址、请求时间、浏览器信息和所请求的动作资源路径。个人训练、饮食与身体记录不会随模型请求上传。清理 3D 离线缓存不会清空个人记录，之后观看动作可能重新下载。

导出的 JSON 包含个人记录且没有加密；校验和仅用于发现损坏。复制会写入系统剪贴板，原生分享可能生成临时文件，由系统缓存管理。请保存到你信任的位置，谨慎选择分享对象；你选择的文件或其他应用之后如何处理数据由其管理。正常读取时，清空当前记录会保留一份替换前本地备份供恢复。读取失败时先归档损坏的原始数据，并保留已有可恢复备份；原始归档不保证可直接恢复。可另行永久删除本地备份。删除网站数据或卸载应用也可能导致本地记录丢失，手动备份应另存。

当前版本未接入 HealthKit，不读取健康数据，不使用相机或麦克风，也不请求这些权限。运动提示、肌肉参与颜色及营养估算仅供参考，不能代表个体实测值；动作尚未获得已识别专业教练的审核认证。''';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  final Future<void> Function()? clearModelCache;
  final Future<bool> Function(String, String, Rect)? exportFile;
  const SettingsScreen({
    super.key,
    required this.state,
    this.clearModelCache,
    this.exportFile,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  AppState get state => widget.state;
  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      message(
        error is StateError ? error.message.toString() : '操作未完成，请重试或使用复制备份。',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> confirmedAction(
    String title,
    String body,
    String label,
    Future<void> Function() action,
  ) async {
    if (await confirm(title, body, label) && mounted) await perform(action);
  }

  Future<void> importBackup() async {
    final controller = TextEditingController();
    BackupPreview? preview;
    String? error;
    final selected = await showDialog<BackupPreview>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(preview == null ? '粘贴手动备份' : '导入预览'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (preview == null) ...[
                  const Text('粘贴完整 JSON。验证通过后，仍需确认才会替换当前记录。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: '备份 JSON'),
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (c.mounted && data?.text != null) {
                          controller.text = data!.text!;
                        }
                      } catch (_) {
                        if (c.mounted) update(() => error = '无法读取剪贴板，请手动粘贴。');
                      }
                    },
                    child: const Text('从剪贴板粘贴'),
                  ),
                ] else ...[
                  Text(
                    '记录版本 ${preview!.sourceVersion}\n按日计划 ${preview!.planCount} 份\n每日记录 ${preview!.logCount} 天\n自定义食物 ${preview!.foodCount} 项\n身体记录 ${preview!.bodyCount} 天',
                  ),
                  if (preview!.dates.isNotEmpty)
                    Text(
                      '记录日期：${preview!.dates.first} 至 ${preview!.dates.last}',
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    '确认后整体替换当前计划、饮食与身体记录、收藏与偏好。替换前先验证保存现有数据：可读记录生成可恢复备份，损坏的原始数据另存归档，并保留已有可恢复备份。',
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, style: const TextStyle(color: sky)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            if (preview == null)
              FilledButton(
                onPressed: () {
                  try {
                    final checked = state.previewBackup(controller.text);
                    update(() {
                      preview = checked;
                      error = null;
                    });
                  } on FormatException catch (e) {
                    update(() => error = e.message);
                  }
                },
                child: const Text('验证并预览'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(c, preview),
                child: const Text('确认替换当前记录'),
              ),
          ],
        ),
      ),
    );
    // The route animation can still reference the controller after it resolves.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (selected != null && mounted) {
      await perform(() async {
        await state.restoreBackup(selected);
        message('备份已导入；替换前数据已保留。');
      });
    }
  }

  Future<void> privacy() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('隐私说明'),
        content: const SingleChildScrollView(
          child: SelectableText(privacyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget item(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      color: surface,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Icon(icon, color: lime),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: busy ? null : action,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('数据与隐私')),
    body: ListenableBuilder(
      listenable: state,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('手动备份', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            '记录保存在此设备。备份包含个人训练、饮食与身体信息，没有加密，请另存到可信位置。',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          item(
            Icons.copy_outlined,
            '复制完整备份',
            '复制 JSON，可粘贴到另一设备导入。',
            () => perform(() async {
              await Clipboard.setData(
                ClipboardData(text: await state.exportBackup()),
              );
              message('完整备份已复制。');
            }),
          ),
          Builder(
            builder: (buttonContext) => item(
              Icons.ios_share,
              kIsWeb ? '下载 JSON 备份' : '保存 / 分享 JSON 备份',
              '导出完整文件；保存位置由你选择。',
              () => perform(() async {
                final box = buttonContext.findRenderObject() as RenderBox?;
                final origin = box == null
                    ? const Rect.fromLTWH(0, 0, 1, 1)
                    : box.localToGlobal(Offset.zero) & box.size;
                final raw = await state.exportBackup();
                final opened = await (widget.exportFile ?? exportBackupFile)(
                  raw,
                  'pulse-backup-${state.today}.json',
                  origin,
                );
                message(
                  opened
                      ? (kIsWeb ? '已请求下载备份文件。' : '已打开系统保存 / 分享。')
                      : '已取消分享，记录仍保存在设备上。',
                );
              }),
            ),
          ),
          item(
            Icons.input_outlined,
            '粘贴 / 导入备份',
            '先验证并预览，再由你确认替换。',
            importBackup,
          ),
          item(
            Icons.restore,
            '恢复替换前备份',
            state.hasPreviousBackup ? '恢复最近一次导入或清空前的本地记录。' : '尚无替换前本地备份。',
            state.hasPreviousBackup
                ? () => confirmedAction(
                    '恢复替换前备份？',
                    '这将整体替换当前记录。可读记录保存为新的替换前备份；读取失败时先归档损坏的原始数据，并保留已有可恢复备份。',
                    '确认恢复',
                    () async {
                      await state.restorePreviousBackup();
                      message('已恢复替换前记录。');
                    },
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text('本地存储', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          item(
            Icons.delete_outline,
            '清空当前记录',
            '重置计划、饮食、身体记录、目标、偏好与收藏；保留替换前数据。',
            () => confirmedAction('清空当前记录？', '当前个人数据将被重置。可读记录保存为可恢复备份；读取失败时先归档损坏的原始数据，并保留已有可恢复备份。需要彻底删除时，请再永久删除本地备份。', '确认清空', () async {
              await state.clearUserData();
              message('当前记录已清空；替换前数据已保留。');
            }),
          ),
          item(
            Icons.delete_forever_outlined,
            '永久删除本地备份',
            '删除替换前备份和读取失败时保留的原始备份。',
            () => confirmedAction(
              '永久删除本地备份？',
              '本地备份将无法再恢复。当前记录与已导出的文件不受影响。',
              '确认删除备份',
              () async {
                await state.deleteLocalBackups();
                message('本地备份已删除。');
              },
            ),
          ),
          item(
            Icons.view_in_ar_outlined,
            '清理 3D 离线缓存',
            '清理已下载模型；个人记录保持完整。',
            () => perform(() async {
              await (widget.clearModelCache ??
                  () async {
                    await (await ModelAssets.shared).clearCache();
                  })();
              message('3D 离线缓存已清理。');
            }),
          ),
          item(
            Icons.privacy_tip_outlined,
            '隐私说明',
            '本地记录、模型下载、手动导出与权限。',
            privacy,
          ),
          if (busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    ),
  );
}
