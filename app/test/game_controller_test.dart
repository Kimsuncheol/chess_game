import 'package:chess_game/features/game/application/game_controller.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:chess_game/services/chess/chess_rules.dart';
import 'package:chess_game/services/stockfish/chess_engine.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:chess_game/services/unity/board_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingGameRepository implements GameRepository {
  @override
  Future<List<GameSession>> loadGames() async => [];
  @override
  Future<void> saveGame(GameSession game) async =>
      throw StateError('Disk full');
}

GameController controllerFor(GameRepository repository) => GameController(
  repository: repository,
  rules: PlaceholderChessRules(),
  engine: PlaceholderStockfishEngine(),
  renderer: PlaceholderUnityRenderer(),
);

void release(GameController controller) {
  controller.dispose();
  controller.renderer.dispose();
  controller.engine.dispose();
}

void main() {
  test('session creation is serialized and resolves random color before persistence', () async {
    final storage = MemoryLocalStorage();
    final controller = controllerFor(storage);
    addTearDown(() => release(controller));
    await controller.load();
    final first = controller.start(
      const GameConfiguration(color: PlayerColor.random),
    );
    final duplicate = await controller.start(const GameConfiguration());
    expect(duplicate, isNull);
    final game = (await first)!;
    expect(game.configuration.color, isNot(PlayerColor.random));
    expect(controller.games, hasLength(1));
    expect((await storage.loadGames()).single, same(game));
    expect(controller.canPlay, isFalse);
    expect(
      () => controller.rules.applyMove(game, 'e2e4'),
      throwsUnsupportedError,
    );
    expect(game.moves, isEmpty);
  });

  test('failed persistence never publishes an uncommitted session', () async {
    final controller = controllerFor(FailingGameRepository());
    addTearDown(() => release(controller));
    expect(await controller.start(const GameConfiguration()), isNull);
    expect(controller.activeGame, isNull);
    expect(controller.games, isEmpty);
    expect(controller.error, isNotNull);
    expect(controller.busy, isFalse);
  });

  test('resignation increments revision, records result once and restores from repository', () async {
    final storage = MemoryLocalStorage();
    final controller = controllerFor(storage);
    addTearDown(() => release(controller));
    final game = (await controller.start(
      const GameConfiguration(color: PlayerColor.black),
    ))!;
    final finished = (await controller.resign(game.id))!;
    expect(finished.result, '1-0');
    expect(finished.revision, game.revision + 1);
    expect(game.isFinished, isFalse);
    expect(controller.activeGame, isNull);
    expect(await controller.resign(game.id), isNull);
    final restored = controllerFor(storage);
    addTearDown(() => release(restored));
    await restored.load();
    expect(restored.find(game.id)?.result, '1-0');
    expect(restored.activeGame, isNull);
  });
}
