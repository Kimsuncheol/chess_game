import 'dart:io';

import 'package:chess_game/app/app_dependencies.dart';
import 'package:chess_game/app/chess_app.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:chess_game/features/settings/domain/app_settings.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:chess_game/services/unity/board_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Directory createTempSettingsDir() {
  final dir = Directory.systemTemp.createTempSync('still_chess_settings_test_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

void main() {
  testWidgets(
    'displays appearance options as list choices (no dropdowns), applies changes immediately, and persists settings locally',
    (tester) async {
      final dir = createTempSettingsDir();
      final deps = AppDependencies.persistent(dir);

      await tester.pumpWidget(
        ChessApp(
          key: UniqueKey(),
          dependencies: deps,
          initialLocation: '/settings',
        ),
      );
      await tester.pumpAndSettle();

      // Requirement 1: Appearance modes are displayed as selectable list options, not dropdowns.
      expect(find.text('System Default'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.byType(RadioListTile<Appearance>), findsNWidgets(3));
      expect(find.byType(DropdownButton), findsNothing);
      expect(find.byType(DropdownMenu), findsNothing);

      // Requirement 3: Selecting Dark applies ThemeMode.dark immediately.
      await tester.tap(find.byKey(const ValueKey('appearance-option-dark')));
      await tester.pump();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.pumpAndSettle();

      // Toggle Sound effects off.
      final soundSwitch = find.byKey(const ValueKey('sound-effects-switch'));
      await tester.ensureVisible(soundSwitch);
      await tester.tap(soundSwitch);
      await tester.pumpAndSettle();
      expect(find.textContaining('Off · Muted on the 3D board'), findsOneWidget);

      // Requirement 2: Verify settings are persisted on disk and restored in a fresh session.
      final storage = FileLocalStorage(directory: dir);
      final persisted = await storage.loadSettings();
      expect(persisted.appearance, Appearance.dark);
      expect(persisted.soundEnabled, isFalse);

      final secondDeps = AppDependencies.persistent(dir);
      await tester.pumpWidget(
        ChessApp(
          key: UniqueKey(),
          dependencies: secondDeps,
          initialLocation: '/settings',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(secondDeps.settings.settings.soundEnabled, isFalse);
    },
  );

  testWidgets(
    'sends sound and camera settings to Unity when the game scene becomes ready and when updated live',
    (tester) async {
      final dir = createTempSettingsDir();
      final renderer = MockUnityBoardRenderer(autoReady: false);
      final deps = AppDependencies.persistent(dir, renderer: renderer);

      await tester.pumpWidget(
        ChessApp(
          key: UniqueKey(),
          dependencies: deps,
          initialLocation: '/settings',
        ),
      );
      await tester.pumpAndSettle();

      // Turn sound effects off and trigger Reset 3D camera before the game scene is ready.
      final soundSwitch = find.byKey(const ValueKey('sound-effects-switch'));
      await tester.ensureVisible(soundSwitch);
      await tester.tap(soundSwitch);
      await tester.pumpAndSettle();

      final resetCameraButton = find.byKey(
        const ValueKey('settings-reset-camera-button'),
      );
      await tester.ensureVisible(resetCameraButton);
      await tester.tap(resetCameraButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('camera-reset-confirmation')),
        findsOneWidget,
      );
      // Scene is not attached/ready yet, so cameraResetCount is still 0.
      expect(renderer.cameraResetCount, 0);

      // Start a game and attach the board; once Unity signals Ready, queued camera reset and sound settings are sent.
      final session = (await deps.game.start(
        const GameConfiguration(
          color: PlayerColor.black,
          difficulty: Difficulty.beginner,
        ),
      ))!;
      final attachFuture = deps.game.attachBoard(session.id);
      await tester.pump();
      renderer.completeReady();
      await attachFuture;
      await tester.pumpAndSettle();

      expect(renderer.currentSettings.soundEnabled, isFalse);
      expect(renderer.currentSettings.cameraFlipped, isTrue);
      expect(renderer.cameraResetCount, 1);
      expect(renderer.currentSnapshot?.soundEnabled, isFalse);

      // Updating sound back to On while the game scene is ready immediately forwards to Unity.
      await deps.settings.update(
        deps.settings.settings.copyWith(soundEnabled: true),
      );
      await tester.pumpAndSettle();
      expect(renderer.currentSettings.soundEnabled, isTrue);

      // Resetting the camera while the game scene is ready immediately triggers Unity camera reset.
      await deps.game.resetCamera();
      await tester.pumpAndSettle();
      expect(renderer.cameraResetCount, 2);
    },
  );

  testWidgets(
    'displays open-source license notices and opens the license page',
    (tester) async {
      final deps = AppDependencies.placeholder();
      await tester.pumpWidget(
        ChessApp(
          key: UniqueKey(),
          dependencies: deps,
          initialLocation: '/settings',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('open-source-notices-card')),
        findsOneWidget,
      );
      expect(
        find.text('• bishop 1.4.4 — MIT License (chess rules)'),
        findsOneWidget,
      );
      expect(
        find.text('• go_router — BSD-3-Clause License (navigation)'),
        findsOneWidget,
      );
      expect(
        find.text('• Flutter & Dart SDK — BSD-3-Clause License (UI & runtime)'),
        findsOneWidget,
      );

      final licensesButton = find.byKey(
        const ValueKey('open-source-licenses-button'),
      );
      await tester.ensureVisible(licensesButton);
      await tester.tap(licensesButton);
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
    },
  );
}
