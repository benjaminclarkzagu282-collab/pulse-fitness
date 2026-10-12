import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

void toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
  );
Future<T?> showAppSheet<T>(BuildContext context, Widget content) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: content,
      ),
    );

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? surface,
      border: Border.all(color: line.withValues(alpha: .6)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class PageTitle extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Widget? trailing;
  const PageTitle({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow.isNotEmpty) ...[
                Text(
                  eyebrow,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;
  const SectionTitle(this.title, {super.key, this.action, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!, style: const TextStyle(fontSize: 12)),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ),
      ],
    ),
  );
}

class Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final IconData? icon;
  const Pill(
    this.label, {
    super.key,
    this.active = false,
    this.onTap,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: active ? lime : surface2,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: active ? lime : line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: active ? bg : muted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? bg : ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Tag extends StatelessWidget {
  final String label;
  final Color color;
  const Tag(this.label, {super.key, this.color = lime});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

class ThinBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const ThinBar(this.value, {super.key, this.color = lime, this.height = 6});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.clamp(0, 1)),
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        color: color,
        backgroundColor: line,
      ),
    ),
  );
}

class Stat extends StatelessWidget {
  final String value, label;
  final Color? color;
  const Stat(this.value, this.label, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w800,
          color: color ?? ink,
          letterSpacing: -.7,
        ),
      ),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

class ScoreRing extends StatelessWidget {
  final int score;
  final double size;
  const ScoreRing(this.score, {super.key, this.size = 122});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: score / 100),
            duration: const Duration(milliseconds: 650),
            builder: (_, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              backgroundColor: line,
              color: lime,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$score',
              style: TextStyle(
                fontSize: size * .31,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text('今日完成度', style: TextStyle(fontSize: 10, color: muted)),
          ],
        ),
      ],
    ),
  );
}

class ExerciseThumb extends StatelessWidget {
  final Exercise exercise;
  final double? width, height;
  final BoxFit fit;
  const ExerciseThumb(
    this.exercise, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });
  @override
  Widget build(BuildContext context) => Image.asset(
    exercise.image,
    width: width,
    height: height,
    fit: fit,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: Icon(Icons.accessibility_new_rounded, size: 52, color: muted),
      ),
    ),
  );
}

class TwoColumns extends StatelessWidget {
  final Widget left, right;
  final double breakAt;
  final int leftFlex, rightFlex;
  const TwoColumns({
    super.key,
    required this.left,
    required this.right,
    this.breakAt = 760,
    this.leftFlex = 3,
    this.rightFlex = 2,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => constraints.maxWidth >= breakAt
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: leftFlex, child: left),
              const SizedBox(width: 22),
              Expanded(flex: rightFlex, child: right),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 22), right],
          ),
  );
}

class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final Widget? action;
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Panel(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon, color: lime, size: 32),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    ),
  );
}

class MiniChart extends StatelessWidget {
  final List<double?> values;
  final List<String> labels;
  const MiniChart(this.values, this.labels, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 100,
        width: double.infinity,
        child: CustomPaint(painter: _ChartPainter(values)),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: labels
            .map(
              (v) =>
                  Text(v, style: const TextStyle(fontSize: 10, color: muted)),
            )
            .toList(),
      ),
    ],
  );
}

class _ChartPainter extends CustomPainter {
  final List<double?> values;
  _ChartPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = i * (size.height - 10) / 2 + 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        previous = null;
        continue;
      }
      final point = Offset(
        6 + i * (size.width - 12) / math.max(1, values.length - 1),
        size.height - 5 - v.clamp(0, 100) / 100 * (size.height - 10),
      );
      if (previous != null) {
        canvas.drawLine(
          previous,
          point,
          Paint()
            ..color = lime
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(point, 4, Paint()..color = lime);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) => true;
}

/// Draws a meal-photo quadrant; alternatives use bundled icons on every platform.
class MealThumbnail extends StatelessWidget {
  final MealChoice meal;
  final double size;
  const MealThumbnail(this.meal, {super.key, this.size = 62});
  @override
  Widget build(BuildContext context) {
    const ids = ['oats', 'chicken', 'yogurt', 'tofu'];
    final index = ids.indexOf(meal.id);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: index < 0
            ? ColoredBox(
                color: surface2,
                child: Center(
                  child: Icon(
                    switch (meal.slot) {
                      0 => Icons.breakfast_dining,
                      1 => Icons.ramen_dining,
                      2 => Icons.local_cafe_outlined,
                      _ => Icons.restaurant,
                    },
                    size: size * .47,
                    color: lime,
                  ),
                ),
              )
            : OverflowBox(
                alignment: Alignment(index.isEven ? -1 : 1, index < 2 ? -1 : 1),
                minWidth: size * 2,
                maxWidth: size * 2,
                minHeight: size * 2,
                maxHeight: size * 2,
                child: Image.asset(
                  'assets/images/meals.png',
                  width: size * 2,
                  height: size * 2,
                  fit: BoxFit.cover,
                ),
              ),
      ),
    );
  }
}
