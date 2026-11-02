import 'dart:async';

import 'package:chess_game/app/app_dependencies.dart';
import 'package:chess_game/app/chess_app.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:chess_game/services/chess/chess_rules.dart';
import 'package:chess_game/services/stockfish/chess_engine.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:chess_game/services/unity/board_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChessRules extends StandardChessRules {
  FakeChessRules({
    Map<String, List<String>>? legalMovesBySquare,
    this.finishOnMoveUci,
    this.finishResult = '1-0',
    this.finishTermination = 'Checkmate',
  }) : _legalMovesBySquare =
           legalMovesBySquare ??
           {
             'e2': ['e2e3', 'e2e4'],
             'e7': ['e7e8q', 'e7e8r', 'e7e8b', 'e7e8n'],
           };

  final Map<String, List<String>> _legalMovesBySquare;
  final String? finishOnMoveUci;
  final String finishResult;
  final String finishTermination;

  @override
  bool get isAvailable => true;

  @override
  List<String> legalMoves(GameSession game, String square) =>
      _legalMovesBySquare[square] ?? const [];

  @override
  GameSession applyMove(GameSession game, String uci) {
    final nextSide = game.sideToMove == PlayerColor.white ? 'b' : 'w';
    final nextFen =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR $nextSide KQkq - 0 1';
    final finishes = finishOnMoveUci == uci;
    return GameSession(
      id: game.id,
      configuration: game.configuration,
      startedAt: game.startedAt,
      revision: game.revision + 1,
      fen: nextFen,
      moves: [...game.moves, uci],
      result: finishes ? finishResult : null,
      termination: finishes ? finishTermination : null,
      endedAt: finishes ? DateTime(2026, 1, 2) : null,
    );
  }
}

class ControllableChessEngine implements ChessEngine {
  ControllableChessEngine({this.autoReplyMove});

  final String? autoReplyMove;
  Completer<String>? _pendingSearch;
  int cancelCount = 0;

  @override
  bool get isAvailable => true;

  @override
  AiDifficultyConfig configFor(Difficulty difficulty) =>
      AiDifficultyConfig.forDifficulty(difficulty);

  @override
  Future<String> search(GameSession position) {
    if (autoReplyMove != null) {
      return Future.value(autoReplyMove!);
    }
    _pendingSearch = Completer<String>();
    return _pendingSearch!.future;
  }

  void completeSearch(String uci) {
    final pending = _pendingSearch;
    if (pending != null && !pending.isCompleted) {
      pending.complete(uci);
    }
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }

  @override
  void dispose() {}
}

Future<AppDependencies> pumpGameScreen(
  WidgetTester tester, {
  required MockUnityBoardRenderer renderer,
  ChessRules? rules,
  ChessEngine? engine,
  GameConfiguration configuration = const GameConfiguration(
    color: PlayerColor.white,
    difficulty: Difficulty.intermediate,
  ),
  bool settle = true,
}) async {
  final storage = MemoryLocalStorage();
  await storage.saveGame(
    GameSession(
      id: 'game-1',
      configuration: configuration,
      startedAt: DateTime(2026, 1, 1),
    ),
  );
  final dependencies = AppDependencies(
    games: storage,
    preferences: storage,
    renderer: renderer,
    rules: rules ?? FakeChessRules(),
    engine: engine ?? ControllableChessEngine(),
  );
  await tester.pumpWidget(
    ChessApp(
      key: UniqueKey(),
      dependencies: dependencies,
      initialLocation: '/game/game-1',
    ),
  );
  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return dependencies;
}

Future<void> tapVisibleText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows loading state until Unity is ready, then displays board and indicators',
    (tester) async {
      final renderer = MockUnityBoardRenderer(autoReady: false);
      final dependencies = await pumpGameScreen(
        tester,
        renderer: renderer,
        settle: false,
      );

      expect(find.byKey(const ValueKey('unity-loading-state')), findsOneWidget);
      expect(find.text('Loading 3D board…'), findsWidgets);
      expect(
        dependencies.game.isPlayerInputEnabledFor(dependencies.game.activeGame),
        isFalse,
      );

      renderer.completeReady();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('unity-loading-state')), findsNothing);
      expect(find.byKey(const ValueKey('unity-board-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-indicator')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-indicator')), findsOneWidget);
      expect(find.text('Player (You)'), findsOneWidget);
      expect(find.text('AI · Intermediate'), findsOneWidget);
      expect(
        dependencies.game.isPlayerInputEnabledFor(dependencies.game.activeGame),
        isTrue,
      );
      expect(renderer.inputEnabled, isTrue);
    },
  );

  testWidgets(
    'prevents player input while AI is thinking and restores turn after AI move',
    (tester) async {
      final renderer = MockUnityBoardRenderer();
      final engine = ControllableChessEngine();
      final dependencies = await pumpGameScreen(
        tester,
        renderer: renderer,
        engine: engine,
      );

      // Select e2 and move to e4 to trigger AI turn.
      renderer.simulateSquareTap('e2');
      await tester.pump();
      renderer.simulateSquareTap('e4');
      await tester.pump();

      expect(dependencies.game.isAiThinking, isTrue);
      expect(find.text('AI is thinking'), findsWidgets);
      expect(renderer.inputEnabled, isFalse);

      final guard = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('unity-input-guard')),
      );
      expect(guard.ignoring, isTrue);

      // Simulated tap during AI thinking must be ignored.
      final movesBefore = dependencies.game.activeGame!.moves.length;
      renderer.simulateSquareTap('e2');
      await tester.pump();
      expect(dependencies.game.activeGame!.moves.length, movesBefore);

      // Complete AI search.
      engine.completeSearch('e7e5');
      await tester.pumpAndSettle();

      expect(dependencies.game.isAiThinking, isFalse);
      expect(dependencies.game.activeGame!.moves, ['e2e4', 'e7e5']);
      expect(renderer.inputEnabled, isTrue);
    },
  );

  testWidgets(
    'handles Unity initialization and communication errors gracefully and recovers on retry',
    (tester) async {
      final renderer = MockUnityBoardRenderer(failOnAttach: true);
      final dependencies = await pumpGameScreen(tester, renderer: renderer);

      expect(find.byKey(const ValueKey('unity-error-state')), findsOneWidget);
      expect(find.text('3D board unavailable'), findsOneWidget);
      expect(renderer.inputEnabled, isFalse);

      // Recover when Retry board connection is pressed.
      renderer.failOnAttach = false;
      await tapVisibleText(tester, 'Retry board connection');

      expect(find.byKey(const ValueKey('unity-error-state')), findsNothing);
      expect(find.byKey(const ValueKey('unity-board-area')), findsOneWidget);
      expect(dependencies.game.isBoardReady, isTrue);
      expect(renderer.inputEnabled, isTrue);

      // Runtime bridge error also disables input and shows recovery UI.
      renderer.emitCommunicationError('Unity bridge disconnected.');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('unity-error-state')), findsOneWidget);
      expect(find.text('Unity bridge disconnected.'), findsWidgets);
      expect(renderer.inputEnabled, isFalse);
    },
  );

  testWidgets(
    'restores the full board state when the Unity view is recreated',
    (tester) async {
      final renderer = MockUnityBoardRenderer();
      final engine = ControllableChessEngine(autoReplyMove: 'e7e5');
      final dependencies = await pumpGameScreen(
        tester,
        renderer: renderer,
        engine: engine,
      );

      // Play a move (e2e4 followed by AI e7e5) and select square e2.
      renderer.simulateSquareTap('e2');
      await tester.pumpAndSettle();
      renderer.simulateSquareTap('e4');
      await tester.pumpAndSettle();
      renderer.simulateSquareTap('e2');
      await tester.pumpAndSettle();

      final attachmentsBefore = renderer.attachmentCount;
      final expectedFen = dependencies.game.activeGame!.fen;
      final expectedRevision = dependencies.game.activeGame!.revision;

      // Recreate Unity view via Reload 3D view button.
      await tapVisibleText(tester, 'Reload 3D view');

      expect(renderer.attachmentCount, greaterThan(attachmentsBefore));
      final restored = renderer.currentSnapshot;
      expect(restored, isNotNull);
      expect(restored!.fen, expectedFen);
      expect(restored.revision, expectedRevision);
      expect(restored.selectedSquare, 'e2');
      expect(restored.legalMoves, ['e2e3', 'e2e4']);
      expect(restored.inputEnabled, isTrue);
    },
  );

  testWidgets(
    'shows promotion selection interface when required and commits chosen piece',
    (tester) async {
      final renderer = MockUnityBoardRenderer();
      final engine = ControllableChessEngine(autoReplyMove: 'a7a6');
      final dependencies = await pumpGameScreen(
        tester,
        renderer: renderer,
        engine: engine,
      );

      // Tap e7 then e8 to trigger promotion selection.
      renderer.simulateSquareTap('e7');
      await tester.pumpAndSettle();
      renderer.simulateSquareTap('e8');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('promotion-selector')), findsOneWidget);
      expect(find.text('Choose promotion piece'), findsOneWidget);
      expect(renderer.inputEnabled, isFalse);

      // Select Knight promotion.
      final knightButton = find.byKey(const ValueKey('promotion-choice-n'));
      await tester.ensureVisible(knightButton);
      await tester.tap(knightButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('promotion-selector')), findsNothing);
      expect(dependencies.game.activeGame!.moves.first, 'e7e8n');
    },
  );

  testWidgets(
    'supports pause, game menu, and confirms destructive restart and resign actions',
    (tester) async {
      final renderer = MockUnityBoardRenderer();
      final engine = ControllableChessEngine(autoReplyMove: 'e7e5');
      final dependencies = await pumpGameScreen(
        tester,
        renderer: renderer,
        engine: engine,
      );

      // Play a move so move list is non-empty.
      renderer.simulateSquareTap('e2');
      await tester.pumpAndSettle();
      renderer.simulateSquareTap('e4');
      await tester.pumpAndSettle();
      expect(dependencies.game.activeGame!.moves, isNotEmpty);

      // Pause game and verify board input is disabled.
      await tapVisibleText(tester, 'Pause game');
      expect(dependencies.game.isPaused, isTrue);
      expect(find.byKey(const ValueKey('paused-panel')), findsOneWidget);
      expect(renderer.inputEnabled, isFalse);

      // Resume game.
      await tapVisibleText(tester, 'Resume game');
      expect(dependencies.game.isPaused, isFalse);
      expect(renderer.inputEnabled, isTrue);

      // Restart game: canceling confirmation keeps moves.
      await tapVisibleText(tester, 'Restart game');
      expect(find.text('Restart this game?'), findsOneWidget);
      await tapVisibleText(tester, 'Keep playing');
      expect(dependencies.game.activeGame!.moves, isNotEmpty);

      // Restart game: confirming resets board moves and increments revision.
      await tapVisibleText(tester, 'Restart game');
      await tapVisibleText(tester, 'Restart');
      expect(dependencies.game.activeGame!.moves, isEmpty);
      expect(dependencies.game.activeGame!.fen, GameSession.initialFen);

      // Resign session: canceling confirmation keeps game active.
      await tapVisibleText(tester, 'Resign session');
      expect(find.text('Resign this session?'), findsOneWidget);
      await tapVisibleText(tester, 'Keep session');
      expect(dependencies.game.activeGame, isNotNull);

      // Resign session: confirming finishes game and transitions to result screen.
      await tapVisibleText(tester, 'Resign session');
      await tapVisibleText(tester, 'Resign');
      expect(find.text('Game result'), findsOneWidget);
      expect(find.text('0-1'), findsOneWidget);
    },
  );

  testWidgets(
    'transitions automatically to Game Result screen when a move ends the game',
    (tester) async {
      final renderer = MockUnityBoardRenderer();
      final rules = FakeChessRules(
        finishOnMoveUci: 'e2e4',
        finishResult: '1-0',
        finishTermination: 'Checkmate',
      );
      await pumpGameScreen(
        tester,
        renderer: renderer,
        rules: rules,
      );

      renderer.simulateSquareTap('e2');
      await tester.pumpAndSettle();
      renderer.simulateSquareTap('e4');
      await tester.pumpAndSettle();

      expect(find.text('Game result'), findsOneWidget);
      expect(find.text('1-0'), findsOneWidget);
      expect(find.text('Checkmate'), findsOneWidget);
    },
  );
}
