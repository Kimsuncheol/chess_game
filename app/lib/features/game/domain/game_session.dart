import 'dart:math';

import 'ai_difficulty_config.dart';
import 'chess/chess_position.dart';

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

enum PromotionPiece {
  queen('q', 'Queen', '♕', '♛'),
  rook('r', 'Rook', '♖', '♜'),
  bishop('b', 'Bishop', '♗', '♝'),
  knight('n', 'Knight', '♘', '♞');

  const PromotionPiece(
    this.uciCode,
    this.label,
    this.whiteSymbol,
    this.blackSymbol,
  );

  final String uciCode;
  final String label;
  final String whiteSymbol;
  final String blackSymbol;

  String symbolFor(PlayerColor color) =>
      color == PlayerColor.black ? blackSymbol : whiteSymbol;
}

class PendingPromotion {
  const PendingPromotion({
    required this.gameId,
    required this.revision,
    required this.from,
    required this.to,
    required this.color,
    this.choices = PromotionPiece.values,
  });

  final String gameId;
  final int revision;
  final String from;
  final String to;
  final PlayerColor color;
  final List<PromotionPiece> choices;
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

  Map<String, Object?> toJson() => {
    'color': color.name,
    'difficulty': difficulty.name,
  };

  factory GameConfiguration.fromJson(Map<String, Object?> json) {
    final color = PlayerColor.values
        .where((c) => c.name == json['color'] && c.isConcrete)
        .firstOrNull;
    final difficulty = Difficulty.values
        .where((d) => d.name == json['difficulty'])
        .firstOrNull;
    if (color == null || difficulty == null) {
      throw const FormatException('Invalid saved game configuration.');
    }
    return GameConfiguration(color: color, difficulty: difficulty);
  }
}

/// Immutable, Flutter-owned state. No renderer or engine may mutate it.
class GameSession {
  GameSession({
    required this.id,
    required this.configuration,
    required this.startedAt,
    this.revision = 0,
    ChessPosition? position,
    String? fen,
    List<String>? moves,
    String? result,
    String? termination,
    this.endedAt,
  }) : position =
           position ??
           (fen != null && fen != initialFen
               ? ChessPosition.fromFen(fen)
               : ChessPosition.initial()),
       _explicitFen = fen,
       _explicitMoves = moves == null ? null : List.unmodifiable(moves),
       _explicitResult = result,
       _explicitTermination = termination;

  static const initialFen = standardInitialFen;
  final String id;
  final GameConfiguration configuration;
  final DateTime startedAt;
  final int revision;
  final ChessPosition position;
  final String? _explicitFen;
  final List<String>? _explicitMoves;
  final String? _explicitResult;
  final String? _explicitTermination;
  final DateTime? endedAt;

  String get fen => _explicitFen ?? position.fen;
  List<String> get moves =>
      _explicitMoves ??
      List.unmodifiable(position.records.map((r) => r.uci));
  List<String> get sanMoves =>
      List.unmodifiable(position.records.map((r) => r.san));
  String? get result =>
      _explicitResult ??
      (position.status.isFinished ? position.status.result : null);
  String? get termination =>
      _explicitTermination ?? position.status.termination?.label;
  bool get isFinished => result != null;

  PlayerColor get humanColor =>
      configuration.color == PlayerColor.black
          ? PlayerColor.black
          : PlayerColor.white;

  PlayerColor get aiColor =>
      humanColor == PlayerColor.white ? PlayerColor.black : PlayerColor.white;

  PlayerColor get sideToMove {
    final fields = fen.split(' ');
    if (fields.length > 1 && fields[1] == 'b') {
      return PlayerColor.black;
    }
    return PlayerColor.white;
  }

  bool get isHumanTurn => !isFinished && sideToMove == humanColor;
  bool get isAiTurn => !isFinished && sideToMove == aiColor;

  GameSession play(String uci, DateTime now) {
    final next = position.play(uci);
    return GameSession(
      id: id,
      configuration: configuration,
      startedAt: startedAt,
      revision: revision + 1,
      position: next,
      endedAt: next.status.isFinished ? now : null,
    );
  }

  GameSession claimDraw(
    DrawClaim claim,
    DateTime now, {
    String? intendedMove,
  }) {
    final next = position.claimDraw(claim, intendedMove: intendedMove);
    return GameSession(
      id: id,
      configuration: configuration,
      startedAt: startedAt,
      revision: revision + 1,
      position: next,
      endedAt: now,
    );
  }

  GameSession undo(DateTime now, {int plies = 1}) {
    final next = position.undo(plies: plies);
    return GameSession(
      id: id,
      configuration: configuration,
      startedAt: startedAt,
      revision: revision + 1,
      position: next,
    );
  }

  GameSession resign(DateTime now) {
    final side = humanColor == PlayerColor.black
        ? ChessSide.black
        : ChessSide.white;
    final next = position.resign(side);
    return GameSession(
      id: id,
      configuration: configuration,
      startedAt: startedAt,
      revision: revision + 1,
      position: next,
      endedAt: now,
    );
  }

  GameSession restart(DateTime now) => GameSession(
    id: id,
    configuration: configuration,
    startedAt: now,
    revision: revision + 1,
    position: ChessPosition.initial(),
  );

  String toPgn() => position.toPgn(
    headers: {
      'White': humanColor == PlayerColor.white
          ? 'Player'
          : 'AI (${configuration.difficulty.label})',
      'Black': humanColor == PlayerColor.black
          ? 'Player'
          : 'AI (${configuration.difficulty.label})',
    },
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'configuration': configuration.toJson(),
    'startedAt': startedAt.toIso8601String(),
    'revision': revision,
    'position': position.toJson(),
    'endedAt': endedAt?.toIso8601String(),
  };

  factory GameSession.fromJson(Map<String, Object?> json) {
    if (json['id'] is! String ||
        json['configuration'] is! Map ||
        json['startedAt'] is! String ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['position'] is! Map) {
      throw const FormatException('Invalid saved game session.');
    }
    final position = ChessPosition.fromJson(
      (json['position'] as Map).cast<String, Object?>(),
    );
    final endedAtStr = json['endedAt'];
    if (endedAtStr != null && endedAtStr is! String) {
      throw const FormatException('Invalid saved game endedAt.');
    }
    return GameSession(
      id: json['id'] as String,
      configuration: GameConfiguration.fromJson(
        (json['configuration'] as Map).cast<String, Object?>(),
      ),
      startedAt: DateTime.parse(json['startedAt'] as String),
      revision: json['revision'] as int,
      position: position,
      endedAt: endedAtStr == null
          ? null
          : DateTime.parse(endedAtStr as String),
    );
  }
}
