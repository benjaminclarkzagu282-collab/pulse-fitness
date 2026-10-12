import 'dart:math' as math;

import 'models.dart';

/// A user's actual measurement, independent of plans and workout load.
class BodyRecord {
  final String date;
  final double? weightKg, waistCm;
  final String note;
  const BodyRecord(this.date, {this.weightKg, this.waistCm, this.note = ''});

  void validate({required String today}) {
    if (!validDayKey(date) || date.compareTo(today) > 0) {
      throw ArgumentError('身体记录日期必须为今天或过去的有效日期。');
    }
    if (weightKg == null && waistCm == null) {
      throw ArgumentError('请至少填写体重或腰围。');
    }
    if (weightKg != null &&
        (!weightKg!.isFinite || weightKg! < 20 || weightKg! > 350)) {
      throw ArgumentError('体重应为 20–350 kg 的有限数值。');
    }
    if (waistCm != null &&
        (!waistCm!.isFinite || waistCm! < 30 || waistCm! > 250)) {
      throw ArgumentError('腰围应为 30–250 cm 的有限数值。');
    }
    if (note.length > 200) throw ArgumentError('备注最多 200 字。');
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'weightKg': weightKg,
    'waistCm': waistCm,
    'note': note,
  };
  factory BodyRecord.fromJson(Map<String, dynamic> j, {required String today}) {
    if (j.keys.any(
          (k) => !const ['date', 'weightKg', 'waistCm', 'note'].contains(k),
        ) ||
        !const ['date', 'weightKg', 'waistCm', 'note'].every(j.containsKey)) {
      throw const FormatException('身体记录字段不完整或包含未知字段。');
    }
    try {
      final record = BodyRecord(
        j['date'] as String,
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        waistCm: (j['waistCm'] as num?)?.toDouble(),
        note: j['note'] as String,
      );
      record.validate(today: today);
      return record;
    } catch (_) {
      throw const FormatException('身体记录的日期、数值或备注无效。');
    }
  }
}

enum BodyMetric { weight, waist }

class BodyPoint {
  final String date;
  final double value;
  const BodyPoint(this.date, this.value);
}

/// Only real measurements become points. Dates with no measurement stay absent.
class BodySeries {
  final List<BodyPoint> points;
  final BodyPoint? latest;
  final String start, end;
  final double minY, maxY;
  factory BodySeries(
    Iterable<BodyRecord> records, {
    required String today,
    required int days,
    required BodyMetric metric,
  }) {
    final date = DateTime.parse(today);
    final start = dayKey(DateTime(date.year, date.month, date.day - days + 1));
    final all = <BodyPoint>[];
    for (final record in records) {
      final value = metric == BodyMetric.weight
          ? record.weightKg
          : record.waistCm;
      if (value != null &&
          validDayKey(record.date) &&
          record.date.compareTo(today) <= 0) {
        all.add(BodyPoint(record.date, value));
      }
    }
    all.sort((a, b) => a.date.compareTo(b.date));
    final points = all.where((p) => p.date.compareTo(start) >= 0).toList();
    final low = points.isEmpty
        ? 0.0
        : points.map((p) => p.value).reduce(math.min);
    final high = points.isEmpty
        ? 1.0
        : points.map((p) => p.value).reduce(math.max);
    final padding = math.max((high - low) * .2, 1.0);
    return BodySeries._(
      List.unmodifiable(points),
      all.lastOrNull,
      start,
      today,
      math.max(0, low - padding),
      high + padding,
    );
  }
  const BodySeries._(
    this.points,
    this.latest,
    this.start,
    this.end,
    this.minY,
    this.maxY,
  );
}
