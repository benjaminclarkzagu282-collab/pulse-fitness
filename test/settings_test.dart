import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/screens/settings.dart';
import 'package:pulse_fitness/ui/theme.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('settings preview clear privacy fit $width', (t) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        await SharedPreferences.getInstance(),
        now: () => DateTime(2026, 10, 3),
      );
      await state.load();
      await state.addWater(250);
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var clears = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: SettingsScreen(
            state: state,
            clearModelCache: () async {
              clears++;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('粘贴 / 导入备份'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), await state.exportBackup());
      await t.tap(find.text('验证并预览'));
      await t.pumpAndSettle();
      expect(find.text('确认替换当前记录'), findsOneWidget);
      expect(state.log.waterMl, 250);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('清空当前记录'), 180);
      await t.tap(find.text('清空当前记录'));
      await t.pumpAndSettle();
      expect(state.log.waterMl, 250);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('清理 3D 离线缓存'), 180);
      await t.tap(find.text('清理 3D 离线缓存'));
      await t.pumpAndSettle();
      expect(clears, 1);
      expect(state.log.waterMl, 250);
      await t.scrollUntilVisible(find.text('隐私说明'), 180);
      await t.tap(find.text('隐私说明'));
      await t.pumpAndSettle();
      expect(find.textContaining('HealthKit'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('invalid preview never displays confirmation', (t) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await state.load();
    await t.pumpWidget(
      MaterialApp(
        theme: pulseTheme(),
        home: SettingsScreen(state: state),
      ),
    );
    await t.tap(find.text('粘贴 / 导入备份'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '{broken');
    await t.tap(find.text('验证并预览'));
    await t.pumpAndSettle();
    expect(find.text('确认替换当前记录'), findsNothing);
    expect(state.logs, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('file export uses complete backup and a visible share origin', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 10, 3),
    );
    await state.load();
    await state.addWater(500);
    String? exported, filename;
    Rect? origin;
    await t.pumpWidget(
      MaterialApp(
        theme: pulseTheme(),
        home: SettingsScreen(
          state: state,
          exportFile: (raw, name, rect) async {
            exported = raw;
            filename = name;
            origin = rect;
            return true;
          },
        ),
      ),
    );
    await t.tap(find.text('保存 / 分享 JSON 备份'));
    await t.pumpAndSettle();
    expect(state.previewBackup(exported!).payloadJson, state.exportJson());
    expect(filename, 'pulse-backup-2026-10-03.json');
    expect(origin!.width, greaterThan(0));
    expect(origin!.height, greaterThan(0));
  });
  testWidgets('explicit import confirmation replaces and clear restore works', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 10, 3),
    );
    await state.load();
    await state.addWater(250);
    final raw = await state.exportBackup();
    await state.addWater(250);
    await t.pumpWidget(
      MaterialApp(
        theme: pulseTheme(),
        home: SettingsScreen(state: state),
      ),
    );
    await t.tap(find.text('粘贴 / 导入备份'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), raw);
    await t.tap(find.text('验证并预览'));
    await t.pumpAndSettle();
    expect(state.log.waterMl, 500);
    await t.tap(find.text('确认替换当前记录'));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(state.log.waterMl, 250);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('清空当前记录'), 150);
    await t.tap(find.text('清空当前记录'));
    await t.pumpAndSettle();
    expect(state.log.waterMl, 250);
    await t.tap(find.text('确认清空'));
    await t.pumpAndSettle();
    expect(state.logs, isEmpty);
    await t.drag(find.byType(ListView), const Offset(0, 350));
    await t.pumpAndSettle();
    await t.tap(find.text('恢复替换前备份'));
    await t.pumpAndSettle();
    expect(state.logs, isEmpty);
    await t.tap(find.text('确认恢复'));
    await t.pumpAndSettle();
    expect(state.log.waterMl, 250);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'confirmed import repairs corrupt storage without promising malformed archive recovery',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final source = AppState(prefs, now: () => DateTime(2026, 10, 3));
      await source.load();
      await source.addWater(250);
      final raw = await source.exportBackup();
      await prefs.setString(AppState.storageKey, '{corrupt original');
      final broken = AppState(prefs, now: source.now);
      await broken.load();
      await t.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: SettingsScreen(state: broken),
        ),
      );
      await t.tap(find.text('粘贴 / 导入备份'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), raw);
      await t.tap(find.text('验证并预览'));
      await t.pumpAndSettle();
      await t.tap(find.text('确认替换当前记录'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(broken.log.waterMl, 250);
      expect(broken.storageError, isNull);
      expect(
        prefs.getString(AppState.unreadableBackupKey),
        '{corrupt original',
      );
      expect(broken.hasPreviousBackup, isFalse);
      expect(find.text('备份已导入；替换前数据已保留。'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
