import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulse_fitness/app.dart';
import 'package:pulse_fitness/core/app_state.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'growth and programs are reachable without changing records at $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final state = AppState(await SharedPreferences.getInstance());
        await state.addWater(250);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(PulseApp(state: state));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('open-progress')), findsOneWidget);
        await tester.tap(find.byKey(const Key('open-progress')));
        await tester.pumpAndSettle();
        expect(find.text('我的成长'), findsOneWidget);
        expect(state.log.setCount, 0);
        expect(state.log.waterMl, 250);
        await tester.pageBack();
        await tester.pumpAndSettle();

        final programEntry = find.byKey(const Key('open-programs'));
        await tester.ensureVisible(programEntry);
        await tester.tap(programEntry);
        await tester.pumpAndSettle();
        expect(find.text('训练方案'), findsOneWidget);
        expect(state.log.setCount, 0);
        expect(state.log.waterMl, 250);
        await tester.pageBack();
        await tester.pumpAndSettle();
        final bodyEntry = find.byKey(const Key('quick-progress'));
        await tester.ensureVisible(bodyEntry);
        await tester.tap(bodyEntry);
        await tester.pumpAndSettle();
        expect(find.text('我的成长'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('quick-library')));
        await tester.tap(find.byKey(const Key('quick-library')));
        await tester.pumpAndSettle();
        expect(find.text('3D 动作库'), findsOneWidget);
        await tester.tap(find.byKey(const Key('nav-0')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('quick-nutrition')));
        await tester.tap(find.byKey(const Key('quick-nutrition')));
        await tester.pumpAndSettle();
        expect(find.text('健康饮食'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('nav-4')));
        await tester.tap(find.byKey(const Key('nav-4')));
        await tester.pumpAndSettle();
        expect(find.text('复盘与下次安排'), findsOneWidget);
        expect(find.byKey(const Key('open-settings')), findsOneWidget);
        await tester.tap(find.byKey(const Key('open-settings')));
        await tester.pumpAndSettle();
        expect(find.text('数据与隐私'), findsOneWidget);
        expect(state.log.setCount, 0);
        expect(state.log.waterMl, 250);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
