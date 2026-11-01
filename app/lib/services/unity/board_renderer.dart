import 'dart:async';

import '../../features/game/domain/game_session.dart';

class BoardInteraction {
  const BoardInteraction({
    required this.gameId,
    required this.revision,
    required this.square,
  });
  final String gameId;
  final int revision;
  final String square;
}

abstract interface class BoardRenderer {
  bool get isAvailable;
  Stream<BoardInteraction> get interactions;
  Future<void> render(GameSession game);
  Future<void> resetCamera();
  void dispose();
}

/// Replace with the versioned JSON adapter only after compatibility validation.
/// This preview neither reports readiness nor accepts moves.
class PlaceholderUnityRenderer implements BoardRenderer {
  final _interactions = StreamController<BoardInteraction>.broadcast();
  GameSession? lastSnapshot;
  @override
  bool get isAvailable => false;
  @override
  Stream<BoardInteraction> get interactions => _interactions.stream;
  @override
  Future<void> render(GameSession game) async {
    lastSnapshot = game;
  }

  @override
  Future<void> resetCamera() async {}
  @override
  void dispose() {
    unawaited(_interactions.close());
  }
}
