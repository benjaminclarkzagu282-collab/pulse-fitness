import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/app.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/screens/settings.dart';

void main() {
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('data settings accessible from every destination at $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await state.addWater(250);
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(PulseApp(state: state));
      await tester.pumpAndSettle();
      for (var nav = 0; nav < 5; nav++) {
        await tester.tap(find.byKey(Key('nav-$nav')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('open-settings')));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('数据与隐私'), findsOneWidget);
        expect(state.log.waterMl, 250);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
