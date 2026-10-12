import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/action_teaching.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../core/muscle_guidance.dart';
import 'components.dart';
import 'theme.dart';

class ActionTeachingCard extends StatelessWidget {
  final Exercise exercise;
  final MuscleGuidance guidance;
  const ActionTeachingCard({
    super.key,
    required this.exercise,
    required this.guidance,
  });
  @override
  Widget build(BuildContext context) {
    final data = teachingFor(exercise.id);
    final sources = List<String>.from(
      (guidance.catalog['exercises'][exercise.id]['referenceUrls'] as List?) ??
          [],
    );
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      title: const Text(
        '动作要点与观察',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: const Text(
        '参考示范 · 待教练复核',
        style: TextStyle(fontSize: 10, color: muted),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final tip in data.checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• $tip',
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                '观察常见偏差',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              for (final mistake in data.commonMistakes)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '• $mistake',
                    style: const TextStyle(
                      fontSize: 11,
                      color: muted,
                      height: 1.6,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                data.alternativeId == null
                    ? '可在计划中调整目标次数、持续时间或负重，再观察动作控制。'
                    : '可比较同类动作：${exerciseById(data.alternativeId!).name}。选择适合自己的版本与目标。',
                style: const TextStyle(fontSize: 11, color: lime, height: 1.6),
              ),
              const SizedBox(height: 10),
              const Text(
                '资料用于动作方向和肌群位置参考，尚未逐帧完成教练审核。颜色不是肌力或激活率测量。',
                style: TextStyle(fontSize: 10, color: muted, height: 1.6),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < sources.length; i++)
                    TextButton.icon(
                      onPressed: () async {
                        var ok = false;
                        try {
                          ok = await launchUrl(
                            Uri.parse(sources[i]),
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {
                          /* Copy remains available without a browser handler. */
                        }
                        if (!ok) {
                          await Clipboard.setData(
                            ClipboardData(text: sources[i]),
                          );
                          if (context.mounted) toast(context, '参考链接已复制');
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 13),
                      label: Text(
                        '参考资料 ${i + 1}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
