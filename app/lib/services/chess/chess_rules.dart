import '../../features/game/domain/chess/chess_position.dart';
import '../../features/game/domain/game_session.dart';

/// Application boundary; the underlying rules and state have no widget imports.
abstract interface class ChessRules {
  bool get isAvailable;

  /// Full UCI choices, including individual promotion suffixes.
  List<String> legalMoves(GameSession game, String square);

  /// Unique destinations for renderer highlights, including one per promotion square.
  List<String> legalDestinations(GameSession game, String square);
  GameSession applyMove(GameSession game, String uci);
  GameSession claimDraw(
    GameSession game,
    DrawClaim claim, {
    String? intendedMove,
  });
  GameSession undo(GameSession game, {int plies = 1});
  GameSession restore(Map<String, Object?> saved);
  String exportPgn(GameSession game);
}

class StandardChessRules implements ChessRules {
  const StandardChessRules();
  @override
  bool get isAvailable => true;
  @override
  List<String> legalMoves(GameSession game, String square) => List.unmodifiable(
    game.position.legalMoves(from: square).map((m) => m.uci),
  );
  @override
  List<String> legalDestinations(GameSession game, String square) =>
      game.position.legalDestinations(square);
  @override
  GameSession applyMove(GameSession game, String uci) =>
      game.play(uci, DateTime.now());
  @override
  GameSession claimDraw(
    GameSession game,
    DrawClaim claim, {
    String? intendedMove,
  }) => game.claimDraw(claim, DateTime.now(), intendedMove: intendedMove);
  @override
  GameSession undo(GameSession game, {int plies = 1}) =>
      game.undo(DateTime.now(), plies: plies);
  @override
  GameSession restore(Map<String, Object?> saved) =>
      GameSession.fromJson(saved);
  @override
  String exportPgn(GameSession game) => game.toPgn();
}

/// Test double retained for tests that explicitly exercise unavailable adapters.
class PlaceholderChessRules extends StandardChessRules {
  @override
  bool get isAvailable => false;
  @override
  List<String> legalMoves(GameSession game, String square) => const [];
  @override
  List<String> legalDestinations(GameSession game, String square) => const [];
  @override
  GameSession applyMove(GameSession game, String uci) =>
      throw UnsupportedError('Chess rules are not connected.');
}
