import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'catalog.dart';
import 'models.dart';
import 'body_metrics.dart';

/// A checksum detects accidental corruption; this is not encryption or identity.
class BackupEnvelope {
  static const format = 'pulse-fitness-backup';
  static const envelopeVersion = 1;
  static String encode(String payloadJson, DateTime createdAt) {
    final payload = jsonDecode(payloadJson);
    return jsonEncode({
      'format': format,
      'envelopeVersion': envelopeVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'checksum': _checksum(payload),
      'payload': payload,
    });
  }

  static String _checksum(Object? payload) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(payload)))).toString();
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}

/// Immutable preview: parsing and validation never touches app state or storage.
class BackupPreview {
  final String payloadJson;
  final int sourceVersion, planCount, logCount, foodCount, bodyCount;
  final List<String> dates;
  BackupPreview._(Map<String, dynamic> payload)
    : payloadJson = jsonEncode(payload),
      sourceVersion = payload['version'],
      planCount = (payload['plans'] as Map).length,
      logCount = (payload['logs'] as Map).length,
      foodCount = (payload['customFoods'] as Map? ?? {}).length,
      bodyCount = (payload['bodyRecords'] as Map? ?? {}).length,
      dates = List.unmodifiable(
        <String>{
          ...(payload['logs'] as Map).keys.cast<String>(),
          ...(payload['bodyRecords'] as Map? ?? {}).keys.cast<String>(),
        }.toList()..sort(),
      );
  factory BackupPreview.parse(String raw, {required String today}) {
    try {
      if (raw.length > 10000000) {
        throw const FormatException('备份超过 10 MB。');
      }
      final decoded = _UniqueJson(raw).decode();
      final root = _map(decoded, '备份');
      Map<String, dynamic> payload = root;
      if (root.containsKey('format') || root.containsKey('payload')) {
        _known(root, [
          'format',
          'envelopeVersion',
          'createdAt',
          'checksum',
          'payload',
        ]);
        _required(root, [
          'format',
          'envelopeVersion',
          'createdAt',
          'checksum',
          'payload',
        ]);
        _integer(root['envelopeVersion'], 1, 1, '封装版本');
        if (root['format'] != BackupEnvelope.format ||
            root['envelopeVersion'] != 1) {
          throw const FormatException('不支持的备份格式或封装版本。');
        }
        final created = root['createdAt'];
        if (created is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$')
                .hasMatch(created) ||
            !validDayKey(created.substring(0, 10)) ||
            DateTime.tryParse(created) == null ||
            DateTime.parse(created)
                    .toUtc()
                    .toIso8601String()
                    .substring(0, 19) !=
                created.substring(0, 19)) {
          throw const FormatException('备份时间无效。');
        }
        payload = _map(root['payload'], '记录内容');
        if (root['checksum'] != BackupEnvelope._checksum(payload)) {
          throw const FormatException('备份校验失败，内容可能不完整。');
        }
      }
      _SnapshotValidator(today).validate(payload);
      return BackupPreview._(payload);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份字段类型或结构不完整。');
    }
  }
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field 应为对象。');
  }
  return value;
}

List<dynamic> _list(Object? value, String field) {
  if (value is! List) {
    throw FormatException('$field 应为列表。');
  }
  return value;
}

void _integer(Object? value, int min, int max, String field) {
  if (value is! int || value < min || value > max) {
    throw FormatException('$field 超出范围或类型错误。');
  }
}

void _number(Object? value, double min, double max, String field) {
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw FormatException('$field 超出范围或不是有限数值。');
  }
}

void _text(Object? value, String field, {int max = 500, bool empty = false}) {
  if (value is! String ||
      value.length > max ||
      (!empty && value.trim().isEmpty)) {
    throw FormatException('$field 文本无效。');
  }
}

void _known(Map<String, dynamic> j, List<String> fields) {
  if (j.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('备份包含不支持的字段，请使用对应版本的应用。');
  }
}

void _required(Map<String, dynamic> j, List<String> keys) {
  for (final key in keys) {
    if (!j.containsKey(key)) {
      throw FormatException('备份缺少 $key。');
    }
  }
}

void _strings(Object? value, String field, {Set<String>? known}) {
  final seen = <String>{};
  for (final v in _list(value, field)) {
    _text(v, field, max: 100);
    if (!seen.add(v as String) || (known != null && !known.contains(v))) {
      throw FormatException('$field 有重复或未知项目。');
    }
  }
}

class _SnapshotValidator {
  final String today;
  _SnapshotValidator(this.today);
  final exerciseIds = exercises.map((e) => e.id).toSet();
  void date(String value, {bool recorded = false}) {
    if (!validDayKey(value) || (recorded && value.compareTo(today) > 0)) {
      throw FormatException('记录日期无效：$value');
    }
  }

  void validate(Map<String, dynamic> j) {
    _known(j, [
      'version',
      'template',
      'plans',
      'logs',
      'mealPlans',
      'favorites',
      'allergens',
      'diet',
      'calorieTarget',
      'waterTarget',
      'proteinTarget',
      'carbsTarget',
      'fatTarget',
      'nutritionTargets',
      'customFoods',
      'bodyRecords',
    ]);
    _required(j, [
      'version',
      'template',
      'plans',
      'logs',
      'mealPlans',
      'favorites',
      'allergens',
      'diet',
      'calorieTarget',
      'waterTarget',
    ]);
    _integer(j['version'], 1, 6, '记录版本');
    final v = j['version'] as int;
    if (v >= 3) {
      _required(j, [
        'proteinTarget',
        'carbsTarget',
        'fatTarget',
        'nutritionTargets',
      ]);
    }
    if (v >= 5) _required(j, ['customFoods']);
    if (v >= 6) _required(j, ['bodyRecords']);
    if (j.containsKey('bodyRecords')) {
      for (final e in _map(j['bodyRecords'], '身体记录').entries) {
        final record = BodyRecord.fromJson(_map(e.value, '身体记录'), today: today);
        if (e.key != record.date) throw const FormatException('身体记录日期键不一致。');
      }
    }
    _integer(j['calorieTarget'], 1000, 4000, '热量目标');
    _integer(j['waterTarget'], 500, 4000, '饮水目标');
    for (final field in ['proteinTarget', 'carbsTarget', 'fatTarget']) {
      if (j.containsKey(field)) {
        _integer(
          j[field],
          1,
          field == 'carbsTarget'
              ? 600
              : field == 'fatTarget'
              ? 200
              : 300,
          field,
        );
      }
    }
    if (!['均衡饮食', '素食优先'].contains(j['diet'])) {
      throw const FormatException('饮食偏好无效。');
    }
    _strings(j['favorites'], '收藏', known: exerciseIds);
    _strings(j['allergens'], '过敏原', known: {'鸡蛋', '乳制品', '大豆', '坚果', '海鲜'});
    plan(_map(j['template'], '计划模板'));
    for (final e in _map(j['plans'], '按日计划').entries) {
      date(e.key);
      plan(_map(e.value, '训练计划'));
    }
    final foods = j.containsKey('customFoods')
        ? _map(j['customFoods'], '自定义食物')
        : <String, dynamic>{};
    for (final e in foods.entries) {
      food(_map(e.value, '食物'));
      if (e.key != e.value['id']) {
        throw const FormatException('食物编号不一致。');
      }
    }
    final entryIds = <String>{};
    for (final e in _map(j['logs'], '每日记录').entries) {
      date(e.key, recorded: true);
      log(_map(e.value, '每日记录'), e.key, v, foods.keys.toSet(), entryIds);
    }
    for (final e in _map(j['mealPlans'], '饮食计划').entries) {
      date(e.key);
      final meals = _list(e.value, '餐食份量');
      if (meals.length != 4) {
        throw const FormatException('饮食计划应包含四个餐次。');
      }
      for (var slot = 0; slot < 4; slot++) {
        final m = _map(meals[slot], '份量');
        _known(m, ['id', 'factor']);
        _required(m, ['id', 'factor']);
        if (!mealChoices.any((c) => c.id == m['id'] && c.slot == slot)) {
          throw const FormatException('餐食编号或餐次无效。');
        }
        _number(m['factor'], .5, 2, '份量');
      }
    }
    if (j.containsKey('nutritionTargets')) {
      for (final e in _map(j['nutritionTargets'], '营养目标').entries) {
        date(e.key);
        final t = _map(e.value, '目标');
        _known(t, ['calories', 'protein', 'carbs', 'fat', 'water']);
        _required(t, ['calories', 'protein', 'carbs', 'fat', 'water']);
        _integer(t['calories'], 1000, 4000, '热量');
        _integer(t['protein'], 1, 300, '蛋白质');
        _integer(t['carbs'], 1, 600, '碳水');
        _integer(t['fat'], 1, 200, '脂肪');
        _integer(t['water'], 500, 4000, '饮水');
      }
    }
  }

  void plan(Map<String, dynamic> j) {
    _known(j, ['title', 'goal', 'equipment', 'minutes', 'days', 'items']);
    _required(j, ['title', 'goal', 'equipment', 'minutes', 'days', 'items']);
    for (final k in ['title', 'goal', 'equipment']) {
      _text(j[k], k, empty: true);
    }
    _integer(j['minutes'], 10, 90, '计划分钟');
    final days = <int>{};
    for (final d in _list(j['days'], '训练日')) {
      _integer(d, 1, 7, '训练日');
      if (!days.add(d as int)) {
        throw const FormatException('训练日重复。');
      }
    }
    final ids = <String>{};
    for (final item in _list(j['items'], '动作')) {
      final i = _map(item, '动作');
      _known(i, ['id', 'sets', 'reps', 'rest']);
      _required(i, ['id', 'sets', 'reps', 'rest']);
      if (!exerciseIds.contains(i['id']) || !ids.add(i['id'])) {
        throw const FormatException('动作编号未知或重复。');
      }
      _integer(i['sets'], 1, 8, '组数');
      _integer(i['reps'], 1, 120, '目标次数');
      _integer(i['rest'], 0, 300, '休息秒数');
    }
  }

  void nutrients(Object? value, {bool per100g = false}) {
    final n = _list(value, '营养数值');
    if (n.length != 4) {
      throw const FormatException('营养数值应包含四项。');
    }
    for (var i = 0; i < 4; i++) {
      _number(
        n[i],
        0,
        per100g ? (i == 0 ? 1000 : 100) : (i == 0 ? 100000 : 10000),
        '营养数值',
      );
    }
  }

  void food(Map<String, dynamic> j) {
    _known(j, ['id', 'name', 'source', 'per100g', 'allergens', 'vegetarian']);
    _required(j, [
      'id',
      'name',
      'source',
      'per100g',
      'allergens',
      'vegetarian',
    ]);
    _text(j['id'], '食物编号', max: 100);
    _text(j['name'], '食物名称', max: 100);
    _text(j['source'], '营养来源');
    nutrients(j['per100g'], per100g: true);
    _strings(j['allergens'], '食物过敏原');
    if (_list(j['allergens'], '过敏原').length > 30 || j['vegetarian'] is! bool) {
      throw const FormatException('食物属性无效。');
    }
    CustomFood.fromJson(j);
  }

  void log(
    Map<String, dynamic> j,
    String key,
    int version,
    Set<String> foodIds,
    Set<String> entryIds,
  ) {
    _known(j, [
      'date',
      'sets',
      'meals',
      'fatigue',
      'water',
      'seconds',
      'waterTarget',
      'setRecords',
      'recovery',
      'foodEntries',
    ]);
    _required(j, ['date', 'sets', 'meals', 'fatigue', 'water', 'seconds']);
    if (version >= 2) _required(j, ['waterTarget']);
    if (version >= 4) _required(j, ['setRecords', 'recovery']);
    if (version >= 5) _required(j, ['foodEntries']);
    if (j['date'] != key) {
      throw const FormatException('日期键与记录日期不一致。');
    }
    _integer(j['water'], 0, 6000, '饮水量');
    _integer(j['seconds'], 0, 10000000, '训练秒数');
    if (j.containsKey('waterTarget')) {
      _integer(j['waterTarget'], 500, 4000, '当天饮水目标');
    }
    for (final f in _list(j['fatigue'], '疲劳')) {
      _integer(f, 1, 3, '疲劳');
    }
    final sets = _map(j['sets'], '完成组');
    for (final e in sets.entries) {
      if (!exerciseIds.contains(e.key)) {
        throw const FormatException('完成组动作未知。');
      }
      final seen = <int>{};
      for (final i in _list(e.value, '组索引')) {
        _integer(i, 0, 7, '组索引');
        if (!seen.add(i as int)) {
          throw const FormatException('完成组重复。');
        }
      }
    }
    for (final e in _map(j['meals'], '已记餐食').entries) {
      final slot = int.tryParse(e.key);
      if (slot == null || '$slot' != e.key || slot < 0 || slot > 3) {
        throw const FormatException('餐次无效。');
      }
      final meal = _map(e.value, '餐食快照');
      _known(meal, ['title', 'nutrients']);
      _required(meal, ['title', 'nutrients']);
      _text(meal['title'], '餐食名称');
      nutrients(meal['nutrients']);
    }
    if (j.containsKey('setRecords')) {
      for (final e in _map(j['setRecords'], '实际组').entries) {
        if (!exerciseIds.contains(e.key)) {
          throw const FormatException('实际动作未知。');
        }
        for (final r in _map(e.value, '组记录').entries) {
          final index = int.tryParse(r.key);
          if (index == null ||
              '$index' != r.key ||
              index < 0 ||
              index > 7 ||
              !_list(sets[e.key], '关联完成组').contains(index)) {
            throw const FormatException('实际组缺少关联完成组。');
          }
          final record = _map(r.value, '实际组数值');
          _known(record, [
            'setIndex',
            'fatigue',
            'elapsedSeconds',
            'target',
            'timed',
            'actualReps',
            'actualSeconds',
            'weightKg',
          ]);
          _required(record, [
            'setIndex',
            'fatigue',
            'elapsedSeconds',
            'target',
            'timed',
            'actualReps',
            'actualSeconds',
            'weightKg',
          ]);
          if (record['setIndex'] != index ||
              record['timed'] != exerciseById(e.key).timed) {
            throw const FormatException('实际组索引或计时属性不符。');
          }
          SetRecord.fromJson(record);
        }
      }
    }
    if (j['recovery'] != null) {
      final r = _map(j['recovery'], '恢复');
      _known(r, ['sleepQuality', 'soreness', 'pain']);
      _required(r, ['sleepQuality', 'soreness', 'pain']);
      RecoveryFeedback.fromJson(r);
    }
    if (j.containsKey('foodEntries')) {
      for (final value in _list(j['foodEntries'], '食物摄入')) {
        final e = _map(value, '摄入快照');
        _known(e, ['id', 'date', 'slot', 'grams', 'food', 'nutrients']);
        _required(e, ['id', 'date', 'slot', 'grams', 'food', 'nutrients']);
        _text(e['id'], '摄入编号', max: 100);
        food(_map(e['food'], '食物快照'));
        nutrients(e['nutrients']);
        _number(e['grams'], double.minPositive, 10000, '克数');
        if (e['date'] != key ||
            !entryIds.add(e['id']) ||
            !foodIds.contains(e['food']['id'])) {
          throw const FormatException('摄入日期、编号或食物引用无效。');
        }
        FoodEntry.fromJson(e);
      }
    }
  }
}

/// JSON decoder which rejects duplicate object keys instead of discarding data.
class _UniqueJson {
  final String raw;
  int index = 0;
  _UniqueJson(this.raw);
  void space() {
    while (index < raw.length && ' \t\r\n'.contains(raw[index])) {
      index++;
    }
  }

  Object? decode() {
    final result = value();
    space();
    if (index != raw.length) {
      throw const FormatException('JSON 尾部无效。');
    }
    return result;
  }

  Object? value() {
    space();
    if (index >= raw.length) {
      throw const FormatException('JSON 不完整。');
    }
    final c = raw[index];
    if (c == '{') return object();
    if (c == '[') return array();
    if (c == '"') return string();
    final start = index;
    while (index < raw.length && !',]} \t\r\n'.contains(raw[index])) {
      index++;
    }
    return jsonDecode(raw.substring(start, index));
  }

  String string() {
    final start = index++;
    while (index < raw.length) {
      if (raw[index] == '\\') {
        index += 2;
      } else if (raw[index++] == '"') {
        return jsonDecode(raw.substring(start, index)) as String;
      }
    }
    throw const FormatException('JSON 字符串不完整。');
  }

  Map<String, dynamic> object() {
    index++;
    space();
    final map = <String, dynamic>{};
    if (index < raw.length && raw[index] == '}') {
      index++;
      return map;
    }
    while (true) {
      space();
      if (index >= raw.length || raw[index] != '"') {
        throw const FormatException('JSON 键无效。');
      }
      final key = string();
      if (map.containsKey(key)) {
        throw FormatException('重复字段 $key。');
      }
      space();
      if (index >= raw.length || raw[index++] != ':') {
        throw const FormatException('JSON 缺少冒号。');
      }
      map[key] = value();
      space();
      if (index >= raw.length) {
        throw const FormatException('JSON 对象不完整。');
      }
      final delimiter = raw[index++];
      if (delimiter == '}') return map;
      if (delimiter != ',') {
        throw const FormatException('JSON 对象无效。');
      }
    }
  }

  List<dynamic> array() {
    index++;
    space();
    final list = <dynamic>[];
    if (index < raw.length && raw[index] == ']') {
      index++;
      return list;
    }
    while (true) {
      list.add(value());
      space();
      if (index >= raw.length) {
        throw const FormatException('JSON 列表不完整。');
      }
      final delimiter = raw[index++];
      if (delimiter == ']') return list;
      if (delimiter != ',') {
        throw const FormatException('JSON 列表无效。');
      }
    }
  }
}
