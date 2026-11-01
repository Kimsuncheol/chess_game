import '../../features/game/domain/game_session.dart';

abstract interface class ChessEngine {
  bool get isAvailable;
  AiDifficultyConfig configFor(Difficulty difficulty);
  Future<String> search(GameSession position);
  Future<void> cancel();
  void dispose();
}

/// No simulated bestmove: callers must check availability before searching.
class PlaceholderStockfishEngine implements ChessEngine {
  @override
  bool get isAvailable => false;
  @override
  AiDifficultyConfig configFor(Difficulty difficulty) =>
      AiDifficultyConfig.forDifficulty(difficulty);
  @override
  Future<String> search(GameSession position) async =>
      throw UnsupportedError('The offline engine is not connected.');
  @override
  Future<void> cancel() async {}
  @override
  void dispose() {}
}
