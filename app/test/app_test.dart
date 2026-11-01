import 'package:chess_game/app/app_dependencies.dart';
import 'package:chess_game/app/chess_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openApp(WidgetTester tester, {String route = '/'}) async {
  await tester.pumpWidget(
    ChessApp(
      key: UniqueKey(),
      dependencies: AppDependencies.placeholder(),
      initialLocation: route,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'setup, board, resignation, result and history form a complete route flow',
    (tester) async {
      await openApp(tester);
      await tapVisible(tester, 'Play vs AI');
      expect(find.text('Game setup'), findsOneWidget);
      await tapVisible(tester, 'Black');
      await tapVisible(tester, 'Advanced');
      await tapVisible(tester, 'Start Game');
      expect(find.text('The board'), findsOneWidget);
      expect(find.textContaining('Black pieces · Advanced opponent'), findsOneWidget);
      await tapVisible(tester, 'Resign session');
      await tapVisible(tester, 'Resign');
      expect(find.text('Game result'), findsOneWidget);
      expect(find.text('1-0'), findsOneWidget);
      await tapVisible(tester, 'View history');
      expect(find.text('1-0 · Resignation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system appearance follows device and overrides remain selected across navigation',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await openApp(tester, route: '/settings');
      expect(
        Theme.of(tester.element(find.text('Appearance'))).brightness,
        Brightness.dark,
      );
      await tapVisible(tester, 'Light');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(
        Theme.of(tester.element(find.text('Appearance'))).brightness,
        Brightness.light,
      );
      await tapVisible(tester, 'Dark');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Settings');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tapVisible(tester, 'System');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
    },
  );

  testWidgets(
    'routes handle missing sessions and unknown paths without crashing',
    (tester) async {
      for (final route in ['/game/missing', '/game/missing/result']) {
        await openApp(tester, route: route);
        expect(find.text('Session not found.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await openApp(tester, route: '/not-a-page');
      expect(find.text('Page not found'), findsOneWidget);
      await tapVisible(tester, 'Return home');
      expect(find.text('Still Chess'), findsOneWidget);
    },
  );

  testWidgets('small phone at 200 percent text has no layout exceptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final route in ['/', '/setup', '/settings', '/history']) {
      await openApp(tester, route: route);
      expect(tester.takeException(), isNull, reason: route);
    }
    await openApp(tester, route: '/setup');
    await tapVisible(tester, 'Start Game');
    expect(tester.takeException(), isNull);
    await tapVisible(tester, 'Resign session');
    await tapVisible(tester, 'Resign');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wide layout and setup controls satisfy Android accessibility guidelines',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openApp(tester);
      expect(tester.takeException(), isNull);
      await openApp(tester, route: '/setup');
      final handle = tester.ensureSemantics();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    },
  );
}
