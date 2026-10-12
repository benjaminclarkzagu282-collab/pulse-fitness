import 'package:flutter/material.dart';

import 'theme.dart';

/// A schematic of the exercise's primary area, not a live measurement.
class MuscleMap extends StatelessWidget {
  final String group, description;
  const MuscleMap({super.key, required this.group, required this.description});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 90,
        height: 136,
        child: CustomPaint(painter: _BodyPainter(group)),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$group · 主要训练部位',
              style: const TextStyle(
                color: lime,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontSize: 12, color: ink, height: 1.6),
            ),
            const SizedBox(height: 8),
            const Text(
              '高亮为目标部位示意',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
      ),
    ],
  );
}

class _BodyPainter extends CustomPainter {
  final String group;
  _BodyPainter(this.group);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 90, size.height / 136);
    final base = Paint()..color = const Color(0xFF46534A);
    final accent = Paint()..color = lime;
    Paint muscle(String area) => group == area || group == '全身' ? accent : base;
    canvas.drawOval(const Rect.fromLTWH(35, 1, 20, 23), base);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(39, 20, 12, 11),
        const Radius.circular(4),
      ),
      base,
    );
    final torso = Path()
      ..moveTo(24, 31)
      ..quadraticBezierTo(45, 23, 66, 31)
      ..lineTo(59, 66)
      ..lineTo(56, 83)
      ..lineTo(34, 83)
      ..lineTo(31, 66)
      ..close();
    canvas.drawPath(torso, base);
    for (final left in [true, false]) {
      final x = left ? 16.0 : 61.0;
      final arm = Paint()
        ..color = muscle('手臂').color
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x + 6, 35), Offset(x, 60), arm);
      canvas.drawLine(Offset(x, 60), Offset(x - (left ? 5 : -5), 84), arm);
      final lx = left ? 36.0 : 54.0;
      final leg = Paint()
        ..color = muscle('腿部').color
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(lx, 83), Offset(lx + (left ? -3 : 3), 108), leg);
      canvas.drawLine(
        Offset(lx + (left ? -3 : 3), 108),
        Offset(lx + (left ? -4 : 4), 128),
        Paint()
          ..color = leg.color
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lx - 8, 127, 15, 7),
          const Radius.circular(3),
        ),
        base,
      );
    }
    final shoulders = group == '手臂' ? accent : muscle('肩部');
    canvas.drawOval(const Rect.fromLTWH(16, 28, 14, 20), shoulders);
    canvas.drawOval(const Rect.fromLTWH(60, 28, 14, 20), shoulders);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(29, 33, 32, 21),
        const Radius.circular(5),
      ),
      muscle(group == '背部' ? '背部' : '胸部'),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(35, 55, 20, 21),
        const Radius.circular(4),
      ),
      muscle('核心'),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(32, 76, 26, 14),
        const Radius.circular(5),
      ),
      muscle('臀部'),
    );
    final seam = Paint()
      ..color = surface
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(45, 34), const Offset(45, 53), seam);
    canvas.drawLine(const Offset(35, 64), const Offset(55, 64), seam);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BodyPainter oldDelegate) => group != oldDelegate.group;
}
