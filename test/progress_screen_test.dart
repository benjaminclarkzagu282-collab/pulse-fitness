import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/body_metrics.dart';
import 'package:pulse_fitness/screens/progress.dart';
import 'package:pulse_fitness/ui/theme.dart';

void main() {
  late AppState state;
  Future<void> init() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 10, 3),
    );
  }

  Future<void> open(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: pulseTheme(),
        home: ProgressScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 180);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0]) {
    testWidgets('growth empty state and entry form fit $width px', (
      tester,
    ) async {
      await init();
      await open(tester, width);
      expect(find.text('我的成长'), findsOneWidget);
      expect(find.text('累计训练天数'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await reveal(tester, find.byKey(const Key('add-body-record')));
      await tester.tap(find.byKey(const Key('add-body-record')));
      await tester.pumpAndSettle();
      expect(find.text('体重（kg）'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('body-weight')), '125.5');
      await tester.enterText(find.byKey(const Key('body-waist')), '110');
      await tester.tap(find.byKey(const Key('save-body-record')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-body-record')), findsNothing);
      expect(state.bodyRecords[state.today]!.weightKg, 125.5);
      expect(find.text('125.5'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'partial records display independent latest metrics and real history',
    (tester) async {
      await init();
      await state.saveBodyRecord(const BodyRecord('2026-10-01', weightKg: 132));
      await state.saveBodyRecord(
        const BodyRecord('2026-10-03', waistCm: 109, note: '晨起'),
      );
      await open(tester, 320);
      await reveal(tester, find.text('132'));
      expect(find.text('132'), findsWidgets);
      expect(find.text('109'), findsWidgets);
      await reveal(tester, find.text('等待下一次记录，形成趋势'));
      expect(find.text('等待下一次记录，形成趋势'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('edit-body-2026-10-01')));
      await tester.tap(find.byKey(const Key('edit-body-2026-10-01')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('body-weight')), '131.5');
      await tester.tap(find.byKey(const Key('save-body-record')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-body-record')), findsNothing);
      expect(state.bodyRecords['2026-10-01']!.weightKg, 131.5);
      await reveal(tester, find.byKey(const Key('remove-body-2026-10-01')));
      await tester.tap(find.byKey(const Key('remove-body-2026-10-01')));
      await tester.pumpAndSettle();
      expect(state.bodyRecords.length, 2);
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(state.bodyRecords.containsKey('2026-10-01'), false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'adding on an existing date requires explicit overwrite confirmation',
    (tester) async {
      await init();
      await state.saveBodyRecord(const BodyRecord('2026-10-03', weightKg: 125));
      await open(tester, 390);
      await reveal(tester, find.byKey(const Key('add-body-record')));
      await tester.tap(find.byKey(const Key('add-body-record')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('body-weight')), '124');
      await tester.tap(find.byKey(const Key('save-body-record')));
      await tester.pumpAndSettle();
      expect(find.text('更新该日身体记录？'), findsOneWidget);
      expect(state.bodyRecords[state.today]!.weightKg, 125);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(state.bodyRecords[state.today]!.weightKg, 125);
      await tester.tap(find.byKey(const Key('save-body-record')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认更新'));
      await tester.pumpAndSettle();
      expect(state.bodyRecords[state.today]!.weightKg, 124);
    },
  );
  testWidgets(
    'failed confirmed body deletion shows persistent retry and preserves stored record',
    (tester) async {
      final preferences = _RejectingPreferences();
      state = AppState(preferences, now: () => DateTime(2026, 10, 3));
      await state.saveBodyRecord(const BodyRecord('2026-10-03', weightKg: 125));
      final stored = preferences.getString(AppState.storageKey);
      preferences.rejectMain = true;
      await open(tester, 320);
      await reveal(tester, find.byKey(const Key('remove-body-2026-10-03')));
      await tester.tap(find.byKey(const Key('remove-body-2026-10-03')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(state.bodyRecords, isEmpty);
      expect(preferences.getString(AppState.storageKey), stored);
      expect(state.storageFailure, StorageFailure.save);
      expect(find.byKey(const Key('progress-storage-error')), findsOneWidget);
      expect(
        find.byKey(const Key('progress-storage-retry')).hitTestable(),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('progress-storage-error')), findsOneWidget);
      preferences.rejectMain = false;
      await tester.tap(find.byKey(const Key('progress-storage-retry')));
      await tester.pumpAndSettle();
      expect(state.storageError, isNull);
      expect(find.byKey(const Key('progress-storage-error')), findsNothing);
      expect(
        jsonDecode(preferences.getString(AppState.storageKey)!)['bodyRecords'],
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed body form save keeps a route retry after transient toast expires',
    (tester) async {
      final preferences = _RejectingPreferences()..rejectMain = true;
      state = AppState(preferences, now: () => DateTime(2026, 10, 3));
      await open(tester, 320);
      await reveal(tester, find.byKey(const Key('add-body-record')));
      await tester.tap(find.byKey(const Key('add-body-record')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('body-weight')), '125');
      await tester.tap(find.byKey(const Key('save-body-record')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-body-record')), findsNothing);
      expect(state.bodyRecords[state.today]!.weightKg, 125);
      expect(preferences.getString(AppState.storageKey), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress-storage-error')), findsOneWidget);
      preferences.rejectMain = false;
      await tester.tap(find.byKey(const Key('progress-storage-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress-storage-error')), findsNothing);
      expect(
        jsonDecode(
          preferences.getString(AppState.storageKey)!,
        )['bodyRecords'][state.today]['weightKg'],
        125,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _RejectingPreferences implements SharedPreferences {
  final Map<String, String> values = {};
  bool rejectMain = false;
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    if (key == AppState.storageKey && rejectMain) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<void> reload() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
