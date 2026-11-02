import 'dart:convert';
import 'dart:io';

import 'package:chess_game/app/app_dependencies.dart';
import 'package:chess_game/app/chess_app.dart';
import 'package:chess_game/features/game/application/game_controller.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:chess_game/features/settings/domain/app_settings.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:chess_game/services/unity/board_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Directory createTempStoreDir() {
  final dir = Directory.systemTemp.createTempSync('still_chess_test_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

void main() {
  test(
    'saves unfinished game after every completed move and restores completed game with date, result, color, difficulty and PGN',
    () async {
      final dir = createTempStoreDir();
      final firstDeps = AppDependencies.persistent(
        dir,
        renderer: MockUnityBoardRenderer(),
      );
      addTearDown(firstDeps.dispose);
      await firstDeps.initialize();

      final started = (await firstDeps.game.start(
        const GameConfiguration(
          color: PlayerColor.white,
          difficulty: Difficulty.advanced,
        ),
      ))!;

      // Move 1 (White): e2e4
      final afterMove1 = (await firstDeps.game.attemptMove(
        started.id,
        'e2e4',
        expectedRevision: 0,
        actor: MoveActor.human,
      ))!;
      expect(afterMove1.isFinished, isFalse);

      // Verify persisted on disk immediately after move 1.
      final storage = FileLocalStorage(directory: dir);
      final loadedAfter1 = (await storage.loadGames()).single;
      expect(loadedAfter1.moves, ['e2e4']);
      expect(loadedAfter1.sanMoves, ['e4']);
      expect(loadedAfter1.fen, afterMove1.fen);
      expect(loadedAfter1.configuration.color, PlayerColor.white);
      expect(loadedAfter1.configuration.difficulty, Difficulty.advanced);
      expect(loadedAfter1.sideToMove, PlayerColor.black);

      // Move 2 (Black): e7e5
      final afterMove2 = (await firstDeps.game.attemptMove(
        started.id,
        'e7e5',
        expectedRevision: 1,
        actor: MoveActor.engine,
      ))!;
      expect(afterMove2.moves, ['e2e4', 'e7e5']);

      // Complete the game by resignation and verify completed game fields & PGN on disk.
      final finished = (await firstDeps.game.resign(started.id))!;
      expect(finished.isFinished, isTrue);
      expect(finished.result, '0-1');

      final rawJson =
          jsonDecode(await storage.gamesFile.readAsString())
              as Map<String, Object?>;
      final savedGameJson =
          (rawJson['games'] as List).single as Map<String, Object?>;
      expect(savedGameJson['result'], '0-1');
      expect(savedGameJson['playerColor'], 'white');
      expect(savedGameJson['difficulty'], 'advanced');
      expect(savedGameJson['date'], isA<String>());
      expect(savedGameJson['pgn'], contains('1. e4 e5 0-1'));
      expect(savedGameJson['pgn'], contains('[Result "0-1"]'));

      final reloadedFinished = (await storage.loadGames()).single;
      expect(reloadedFinished.isFinished, isTrue);
      expect(reloadedFinished.result, '0-1');
      expect(reloadedFinished.termination, 'Resignation');
      expect(reloadedFinished.configuration.color, PlayerColor.white);
      expect(reloadedFinished.configuration.difficulty, Difficulty.advanced);
      expect(reloadedFinished.toPgn(), contains('1. e4 e5 0-1'));
    },
  );

  testWidgets(
    'Continue Game restores position, move history, player color, AI difficulty, and status from persistent storage',
    (tester) async {
      final dir = createTempStoreDir();

      // Session 1: start a game and play 3 plies (1. e4 e5 2. Nf3).
      final writerDeps = AppDependencies.persistent(
        dir,
        renderer: MockUnityBoardRenderer(),
      );
      await writerDeps.initialize();
      final session = (await writerDeps.game.start(
        const GameConfiguration(
          color: PlayerColor.black,
          difficulty: Difficulty.beginner,
        ),
      ))!;
      await writerDeps.game.attemptMove(
        session.id,
        'e2e4',
        expectedRevision: 0,
        actor: MoveActor.engine,
      );
      await writerDeps.game.attemptMove(
        session.id,
        'e7e5',
        expectedRevision: 1,
        actor: MoveActor.human,
      );
      final afterThreePlies = (await writerDeps.game.attemptMove(
        session.id,
        'g1f3',
        expectedRevision: 2,
        actor: MoveActor.engine,
      ))!;
      writerDeps.dispose();

      // Session 2: cold start app from the same persistent directory and tap Continue Game.
      final readerRenderer = MockUnityBoardRenderer();
      final readerDeps = AppDependencies.persistent(
        dir,
        renderer: readerRenderer,
      );
      await tester.pumpWidget(
        ChessApp(key: UniqueKey(), dependencies: readerDeps),
      );
      await tester.pumpAndSettle();

      final continueButton = find.text('Continue Game');
      expect(continueButton, findsOneWidget);
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(find.text('The board'), findsOneWidget);
      expect(
        find.textContaining('Black pieces · Beginner opponent'),
        findsOneWidget,
      );
      expect(find.text('Your turn · Black to move'), findsOneWidget);
      expect(find.text('e4 · e5 · Nf3'), findsOneWidget);

      final restored = readerDeps.game.activeGame!;
      expect(restored.fen, afterThreePlies.fen);
      expect(restored.moves, ['e2e4', 'e7e5', 'g1f3']);
      expect(restored.sanMoves, ['e4', 'e5', 'Nf3']);
      expect(restored.configuration.color, PlayerColor.black);
      expect(restored.configuration.difficulty, Difficulty.beginner);
      expect(restored.isHumanTurn, isTrue);
    },
  );

  testWidgets(
    'History screen lists previous games and allows inspecting move list and PGN',
    (tester) async {
      final dir = createTempStoreDir();
      final storage = FileLocalStorage(directory: dir);

      // Save a completed Scholar's Mate game.
      final completed = GameSession(
        id: 'completed-scholars-mate',
        configuration: const GameConfiguration(
          color: PlayerColor.white,
          difficulty: Difficulty.intermediate,
        ),
        startedAt: DateTime(2026, 11, 2, 10, 0),
      )
          .play('e2e4', DateTime(2026, 11, 2, 10, 1))
          .play('e7e5', DateTime(2026, 11, 2, 10, 2))
          .play('f1c4', DateTime(2026, 11, 2, 10, 3))
          .play('b8c6', DateTime(2026, 11, 2, 10, 4))
          .play('d1h5', DateTime(2026, 11, 2, 10, 5))
          .play('g8f6', DateTime(2026, 11, 2, 10, 6))
          .play('h5f7', DateTime(2026, 11, 2, 10, 7));
      await storage.saveGame(completed);

      final deps = AppDependencies.persistent(dir);
      await tester.pumpWidget(
        ChessApp(
          key: UniqueKey(),
          dependencies: deps,
          initialLocation: '/history',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1-0 · Checkmate'), findsOneWidget);
      expect(
        find.textContaining('White · Intermediate'),
        findsOneWidget,
      );
      expect(find.textContaining('2026-11-02 · 7 moves'), findsOneWidget);

      // Open Move List Inspector.
      final inspectButton = find.byKey(
        const ValueKey('inspect-moves-completed-scholars-mate'),
      );
      await tester.ensureVisible(inspectButton);
      await tester.tap(inspectButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('move-inspector-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('1. e4 (e2e4)'), findsOneWidget);
      expect(find.textContaining('4. Qxf7# (h5f7)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inspector-pgn-text')),
        findsOneWidget,
      );

      // Step backward one ply in the inspector.
      final prevPlyButton = find.byKey(const ValueKey('inspector-prev-ply'));
      await tester.ensureVisible(prevPlyButton);
      await tester.tap(prevPlyButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('After move 6 of 7 (Nf6)'), findsOneWidget);

      // Close inspector.
      final closeInspectorButton = find.byKey(
        const ValueKey('close-move-inspector-button'),
      );
      await tester.ensureVisible(closeInspectorButton);
      await tester.tap(closeInspectorButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('move-inspector-dialog')),
        findsNothing,
      );
    },
  );

  test(
    'handles corrupted, truncated, or partially invalid saved data without crashing',
    () async {
      final dir = createTempStoreDir();
      final storage = FileLocalStorage(directory: dir);

      // 1. Truncated / malformed JSON in both games and settings files.
      await storage.gamesFile.writeAsString('{not-valid-json');
      await storage.settingsFile.writeAsString('[1, 2, 3]');

      expect(await storage.loadGames(), isEmpty);
      expect(
        (await storage.loadSettings()).appearance,
        Appearance.system,
      );
      expect(storage.corruptedRecordsSkipped, greaterThanOrEqualTo(2));
      expect(
        await File('${storage.gamesFile.path}.corrupt').exists(),
        isTrue,
      );

      // 2. Envelope with a mix of valid and corrupted game entries.
      final validSession = GameSession(
        id: 'valid-game-1',
        configuration: const GameConfiguration(
          color: PlayerColor.black,
          difficulty: Difficulty.beginner,
        ),
        startedAt: DateTime(2026, 11, 2),
      ).play('e2e4', DateTime(2026, 11, 2, 0, 1));

      final mixedPayload = {
        'schemaVersion': 1,
        'games': [
          'not-a-map',
          {'id': '', 'configuration': {}}, // incomplete record
          {
            // invalid un-resolved random color in saved state
            ...validSession.toJson(),
            'id': 'bad-color-game',
            'configuration': {'color': 'random', 'difficulty': 'beginner'},
          },
          {
            // illegal move in move history
            ...validSession.toJson(),
            'id': 'illegal-move-game',
            'position': {
              ...validSession.position.toJson(),
              'moves': ['e2e5'],
            },
          },
          validSession.toJson(),
        ],
      };
      await storage.gamesFile.writeAsString(jsonEncode(mixedPayload));

      final recoveredGames = await storage.loadGames();
      expect(recoveredGames, hasLength(1));
      expect(recoveredGames.single.id, 'valid-game-1');
      expect(recoveredGames.single.moves, ['e2e4']);
    },
  );
}

