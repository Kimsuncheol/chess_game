import 'dart:math';

import 'ai_difficulty_config.dart';

export 'ai_difficulty_config.dart';

enum PlayerColor {
  white('White', 'Move first with the light pieces.'),
  black('Black', 'Respond to the opening with the dark pieces.'),
  random('Random', 'Assign White or Black automatically when the game starts.');

  const PlayerColor(this.label, this.description);
  final String label;
  final String description;

  bool get isConcrete => this == PlayerColor.white || this == PlayerColor.black;

  PlayerColor resolve([Random? random]) {
    if (this != PlayerColor.random) return this;
    return (random ?? Random()).nextBool()
        ? PlayerColor.white
        : PlayerColor.black;
  }
}

enum Difficulty {
  beginner(
    'Beginner',
    'Plays at a forgiving pace and leaves room to learn the fundamentals.',
  ),
  intermediate(
    'Intermediate',
    'Plays a steady, balanced game that rewards sound development and tactics.',
  ),
  advanced(
    'Advanced',
    'Searches deeper and punishes mistakes for a sharper tactical challenge.',
  );

  const Difficulty(this.label, this.description);
  final String label;
  final String description;

  AiDifficultyConfig get aiConfig => AiDifficultyConfig.forDifficulty(this);
}

class GameConfiguration {
  const GameConfiguration({
    this.color = PlayerColor.white,
    this.difficulty = Difficulty.intermediate,
  });
  final PlayerColor color;
  final Difficulty difficulty;

  AiDifficultyConfig get aiConfig => difficulty.aiConfig;

  GameConfiguration resolve([Random? random]) => GameConfiguration(
    color: color.resolve(random),
    difficulty: difficulty,
  );
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
