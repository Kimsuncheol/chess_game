import 'package:chess_game/app/app_dependencies.dart';
import 'package:chess_game/app/chess_app.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:chess_game/services/chess/chess_rules.dart';
import 'package:chess_game/services/stockfish/chess_engine.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:chess_game/services/unity/board_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppDependencies dependenciesFor(MemoryLocalStorage storage) => AppDependencies(
  games: storage,
  preferences: storage,
  rules: PlaceholderChessRules(),
  renderer: PlaceholderUnityRenderer(),
  engine: PlaceholderStockfishEngine(),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Home actions are accessible in ${brightness.name} appearance',
      (tester) async {
        tester.view.physicalSize = const Size(420, 1100);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            ChessApp(dependencies: AppDependencies.placeholder()),
          );
          await tester.pumpAndSettle();
          expect(find.text('Still Chess'), findsOneWidget);
          expect(find.text('Continue Game'), findsNothing);
          for (final label in ['Play vs AI', 'Game History', 'Settings']) {
            expect(find.bySemanticsLabel(label), findsOneWidget);
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await tester.tap(find.text('Game History'));
          await tester.pumpAndSettle();
          expect(find.text('History'), findsOneWidget);
          expect(find.text('A clean slate'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          handle.dispose();
        }
      },
    );
  }

  testWidgets('Continue opens an unfinished game loaded from the repository', (
    tester,
  ) async {
    final storage = MemoryLocalStorage();
    // Test-only fixture. Production repositories are never seeded with samples.
    await storage.saveGame(
      GameSession(
        id: 'test-saved-game',
        configuration: const GameConfiguration(color: PlayerColor.black),
        startedAt: DateTime(2026, 1, 1),
      ),
    );
    await tester.pumpWidget(ChessApp(dependencies: dependenciesFor(storage)));
    await tester.pumpAndSettle();
    final continueButton = find.text('Continue Game');
    expect(continueButton, findsOneWidget);
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('The board'), findsOneWidget);
    expect(find.textContaining('Black pieces'), findsOneWidget);
    expect(find.text('Session not found.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed games never show Continue Game', (tester) async {
    final storage = MemoryLocalStorage();
    final game = GameSession(
      id: 'test-completed-game',
      configuration: const GameConfiguration(),
      startedAt: DateTime(2026, 1, 1),
    );
    await storage.saveGame(game.resign(DateTime(2026, 1, 2)));
    await tester.pumpWidget(ChessApp(dependencies: dependenciesFor(storage)));
    await tester.pumpAndSettle();
    expect(find.text('Continue Game'), findsNothing);
    expect(find.text('Play vs AI'), findsOneWidget);
  });
}
