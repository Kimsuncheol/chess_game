import 'dart:async';

import 'package:chess_game/features/game/application/game_controller.dart';
import 'package:chess_game/features/game/domain/chess/chess_position.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:chess_game/services/chess/chess_rules.dart';
import 'package:chess_game/services/stockfish/chess_engine.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:chess_game/services/unity/board_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledRepository extends MemoryLocalStorage {
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> saveGame(GameSession game) async {
    if (pending != null) await pending!.future;
    if (fail) throw StateError('Storage unavailable');
    await super.saveGame(game);
  }
}

GameController createController(
  GameRepository repository, {
  BoardRenderer? renderer,
}) => GameController(
  repository: repository,
  rules: const StandardChessRules(),
  engine: PlaceholderStockfishEngine(),
  renderer: renderer ?? PlaceholderUnityRenderer(),
);
void disposeController(GameController controller) {
  controller.dispose();
  controller.renderer.dispose();
  controller.engine.dispose();
}

void main() {
  test('human and engine moves share validation, turn checks and stale-revision rejection', () async {
    final storage = MemoryLocalStorage();
    final controller = createController(storage);
    addTearDown(() => disposeController(controller));
    final game = (await controller.start(const GameConfiguration()))!;
    expect(controller.legalDestinations(game.id, 'e2'), ['e3', 'e4']);
    expect(
      await controller.attemptMove(
        game.id,
        'e7e5',
        expectedRevision: 0,
        actor: MoveActor.engine,
      ),
      isNull,
    );
    final afterWhite = (await controller.attemptMove(
      game.id,
      'e2e4',
      expectedRevision: 0,
      actor: MoveActor.human,
    ))!;
    expect(afterWhite.revision, 1);
    expect(afterWhite.sanMoves, ['e4']);
    expect(
      await controller.attemptMove(
        game.id,
        'd2d4',
        expectedRevision: 1,
        actor: MoveActor.human,
      ),
      isNull,
    );
    expect(
      await controller.attemptMove(
        game.id,
        'e7e5',
        expectedRevision: 0,
        actor: MoveActor.engine,
      ),
      isNull,
    );
    final afterBlack = (await controller.attemptMove(
      game.id,
      'e7e5',
      expectedRevision: 1,
      actor: MoveActor.engine,
    ))!;
    expect(afterBlack.moves, ['e2e4', 'e7e5']);
    expect((await storage.loadGames()).single.fen, afterBlack.fen);
    expect(
      (controller.renderer as PlaceholderUnityRenderer).lastSnapshot?.fen,
      afterBlack.fen,
    );
    expect(controller.exportPgn(game.id), contains('1. e4 e5 *'));
    // Native integrations remain unavailable; rules alone do not enable preview input.
    expect(controller.canPlay, isFalse);
  });

  test(
    'an uncommitted or failed write never changes canonical state or renderer',
    () async {
      final storage = ControlledRepository();
      final controller = createController(storage);
      addTearDown(() => disposeController(controller));
      final game = (await controller.start(const GameConfiguration()))!;
      final gate = Completer<void>();
      storage.pending = gate;
      final move = controller.attemptMove(
        game.id,
        'e2e4',
        expectedRevision: 0,
        actor: MoveActor.human,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.find(game.id)?.fen, game.fen);
      expect(
        (controller.renderer as PlaceholderUnityRenderer)
            .lastSnapshot
            ?.revision,
        0,
      );
      expect(
        await controller.attemptMove(
          game.id,
          'd2d4',
          expectedRevision: 0,
          actor: MoveActor.human,
        ),
        isNull,
      );
      storage.fail = true;
      gate.complete();
      expect(await move, isNull);
      expect(controller.find(game.id)?.revision, 0);
      expect(controller.find(game.id)?.moves, isEmpty);
      expect((await storage.loadGames()).single.moves, isEmpty);
      storage.pending = null;
      storage.fail = false;
      expect(
        await controller.attemptMove(
          game.id,
          'e2e4',
          expectedRevision: 0,
          actor: MoveActor.human,
        ),
        isNotNull,
      );
    },
  );

  test('controller restores replay-validated state and undo rejects old engine work', () async {
    final storage = MemoryLocalStorage();
    final controller = createController(storage);
    addTearDown(() => disposeController(controller));
    final game = (await controller.start(const GameConfiguration()))!;
    await controller.attemptMove(
      game.id,
      'e2e4',
      expectedRevision: 0,
      actor: MoveActor.human,
    );
    final undone = (await controller.undo(game.id, expectedRevision: 1))!;
    expect(undone.revision, 2);
    expect(undone.fen, standardInitialFen);
    expect(
      await controller.attemptMove(
        game.id,
        'e7e5',
        expectedRevision: 1,
        actor: MoveActor.engine,
      ),
      isNull,
    );
    final restored = createController(storage);
    addTearDown(() => disposeController(restored));
    await restored.load();
    expect(restored.activeGame?.id, game.id);
    expect(restored.activeGame?.revision, 2);
    expect(restored.activeGame?.moves, isEmpty);
  });

  test('controller validates draw claimant turn and persists claims without a move', () async {
    final storage = MemoryLocalStorage();
    final game = GameSession(
      id: 'draw-session',
      configuration: const GameConfiguration(),
      startedAt: DateTime(2026, 11, 2),
      position: ChessPosition.fromFen('4k2r/8/8/8/8/8/8/R3K3 w - - 100 51'),
    );
    await storage.saveGame(game);
    final controller = createController(storage);
    addTearDown(() => disposeController(controller));
    await controller.load();
    expect(
      await controller.claimDraw(
        game.id,
        DrawClaim.fiftyMove,
        expectedRevision: 0,
        actor: MoveActor.engine,
      ),
      isNull,
    );
    final claimed = (await controller.claimDraw(
      game.id,
      DrawClaim.fiftyMove,
      expectedRevision: 0,
      actor: MoveActor.human,
    ))!;
    expect(claimed.result, '1/2-1/2');
    expect(claimed.moves, isEmpty);
    expect(claimed.revision, 1);
    expect(controller.activeGame, isNull);
    final saved = (await storage.loadGames()).single;
    expect(
      GameSession.fromJson(saved.toJson()).position.status.termination,
      ChessTermination.fiftyMoveClaim,
    );
  });
}
