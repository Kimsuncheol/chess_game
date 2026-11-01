import '../../features/game/domain/game_session.dart';

abstract interface class ChessRules {
  bool get isAvailable;
  List<String> legalMoves(GameSession game, String square);
  GameSession applyMove(GameSession game, String uci);
}

/// Fail closed until a Dart rules implementation passes conformance testing.
class PlaceholderChessRules implements ChessRules {
  @override
  bool get isAvailable => false;
  @override
  List<String> legalMoves(GameSession game, String square) => const [];
  @override
  GameSession applyMove(GameSession game, String uci) =>
      throw UnsupportedError('Chess rules are not connected.');
}
