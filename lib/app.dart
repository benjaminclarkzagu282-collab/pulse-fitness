import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'ui/theme.dart';
import 'screens/today.dart';
import 'screens/plan.dart';
import 'screens/library.dart';
import 'screens/nutrition.dart';
import 'screens/insights.dart';
import 'screens/settings.dart';
import 'screens/progress.dart';

class PulseApp extends StatelessWidget {
  final AppState state;
  const PulseApp({super.key, required this.state});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PULSE · 动起来',
    debugShowCheckedModeBanner: false,
    theme: pulseTheme(),
    home: _Shell(state: state),
  );
}

class _Shell extends StatefulWidget {
  final AppState state;
  const _Shell({required this.state});
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int index = 0;
  late final Timer _clock;
  late String day;
  static const labels = ['今天', '计划', '动作', '饮食', '记录'];
  static const icons = [
    Icons.grid_view_rounded,
    Icons.calendar_month_outlined,
    Icons.fitness_center_rounded,
    Icons.restaurant_rounded,
    Icons.bar_chart_rounded,
  ];
  @override
  void initState() {
    super.initState();
    day = widget.state.today;
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (day != widget.state.today && mounted) {
        setState(() => day = widget.state.today);
      }
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  void go(int value) => setState(() => index = value);
  void openProgress() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProgressScreen(state: widget.state),
    ),
  );
  void openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(state: widget.state),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final wide = MediaQuery.sizeOf(context).width >= 1000;
      final pages = [
        TodayScreen(state: state, navigate: go),
        PlanScreen(state: state, openLibrary: () => go(2)),
        LibraryScreen(state: state),
        NutritionScreen(state: state),
        InsightsScreen(state: state),
      ];
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 218,
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(25, 32, 20, 36),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: lime,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.bolt_rounded,
                                color: bg,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'PULSE',
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 26),
                        child: Text(
                          '你的日常训练空间',
                          style: TextStyle(
                            fontSize: 10,
                            color: muted,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < labels.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          child: Material(
                            color: index == i
                                ? lime.withValues(alpha: .1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            child: InkWell(
                              key: Key('nav-$i'),
                              borderRadius: BorderRadius.circular(13),
                              onTap: () => go(i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 17,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      icons[i],
                                      size: 20,
                                      color: index == i ? lime : muted,
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      labels[i],
                                      style: TextStyle(
                                        color: index == i ? ink : muted,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (index == i)
                                      const Icon(
                                        Icons.arrow_forward,
                                        size: 15,
                                        color: lime,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: surface,
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.eco_outlined, size: 24, color: lime),
                              SizedBox(height: 10),
                              Text(
                                '按自己的节奏',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                '每一点进步\n都值得被看见。',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                  height: 1.7,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(25, 0, 20, 25),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 12, color: muted),
                            SizedBox(width: 6),
                            Text(
                              '记录保存在本机',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: wide ? 70 : 52,
                      padding: EdgeInsets.symmetric(horizontal: wide ? 36 : 16),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            wide
                                ? '我的空间  /  ${labels[index]}'
                                : 'PULSE  /  ${labels[index]}',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                          const Spacer(),
                          if (wide)
                            const Icon(Icons.circle, size: 6, color: lime),
                          if (wide) const SizedBox(width: 7),
                          if (wide)
                            const Text(
                              '本地记录已开启',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                          const SizedBox(width: 12),
                          IconButton(
                            key: const Key('open-progress'),
                            tooltip: '我的成长',
                            onPressed: openProgress,
                            icon: const Icon(
                              Icons.insights_rounded,
                              color: ink,
                              size: 21,
                            ),
                          ),
                          IconButton(
                            key: const Key('open-settings'),
                            tooltip: '设置与数据',
                            onPressed: openSettings,
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: lime,
                              size: 21,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.storageError != null)
                      MaterialBanner(
                        content: Text(state.storageError!),
                        actions: [
                          TextButton(
                            onPressed: state.retrySave,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: SingleChildScrollView(
                          key: ValueKey(index),
                          padding: EdgeInsets.fromLTRB(
                            wide ? 34 : 16,
                            wide ? 28 : 20,
                            wide ? 34 : 16,
                            32,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1220),
                              child: pages[index],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : Container(
                decoration: const BoxDecoration(
                  color: bg,
                  border: Border(top: BorderSide(color: line)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 5),
                    child: Row(
                      children: List.generate(
                        5,
                        (i) => Expanded(
                          child: InkWell(
                            key: Key('nav-$i'),
                            onTap: () => go(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icons[i],
                                    color: index == i ? lime : muted,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    labels[i],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: index == i
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: index == i ? lime : muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
    },
  );
}
