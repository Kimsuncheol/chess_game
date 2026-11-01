enum PlayerColor {
  white('White'),
  black('Black'),
  random('Random');

  const PlayerColor(this.label);
  final String label;
}

enum Difficulty {
  relaxed('Relaxed', 'Take your time and explore.'),
  balanced('Balanced', 'A thoughtful everyday challenge.'),
  challenging('Challenging', 'Room to sharpen your game.');

  const Difficulty(this.label, this.description);
  final String label;
  final String description;
}

class GameConfiguration {
  const GameConfiguration({
    this.color = PlayerColor.white,
    this.difficulty = Difficulty.balanced,
  });
  final PlayerColor color;
  final Difficulty difficulty;
}

/// Immutable, Flutter-owned state. No renderer or engine may mutate it.
class GameSession {
  GameSession({
    required this.id,
    required this.configuration,
    required this.startedAt,
    this.revision = 0,
    this.fen = initialFen,
    List<String> moves = const [],
    this.result,
    this.termination,
    this.endedAt,
  }) : moves = List.unmodifiable(moves);

  static const initialFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  final String id;
  final GameConfiguration configuration;
  final DateTime startedAt;
  final int revision;
  final String fen;
  final List<String> moves;
  final String? result;
  final String? termination;
  final DateTime? endedAt;
  bool get isFinished => result != null;

  GameSession resign(DateTime now) => GameSession(
    id: id,
    configuration: configuration,
    startedAt: startedAt,
    revision: revision + 1,
    fen: fen,
    moves: moves,
    result: configuration.color == PlayerColor.white ? '0-1' : '1-0',
    termination: 'Resignation',
    endedAt: now,
  );
}
