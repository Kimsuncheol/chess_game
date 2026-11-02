import 'dart:async';

import '../../features/game/domain/game_session.dart';

enum GamePhase {
  loading('Loading 3D board…'),
  humanTurn('Your turn'),
  promotionPending('Promotion required'),
  applyingMove('Applying move…'),
  aiThinking('AI is thinking'),
  paused('Game paused'),
  finished('Session complete'),
  recoverableError('Board connection issue');

  const GamePhase(this.label);
  final String label;
}

class BoardSnapshot {
  const BoardSnapshot({
    required this.game,
    this.selectedSquare,
    this.legalMoves = const [],
    this.pendingPromotion,
    this.phase = GamePhase.humanTurn,
    this.inputEnabled = false,
    this.cameraFlipped = false,
  });

  final GameSession game;
  final String? selectedSquare;
  final List<String> legalMoves;
  final PendingPromotion? pendingPromotion;
  final GamePhase phase;
  final bool inputEnabled;
  final bool cameraFlipped;

  String get gameId => game.id;
  int get revision => game.revision;
  String get fen => game.fen;
}

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

sealed class BoardBridgeEvent {
  const BoardBridgeEvent();
}

class BoardBridgeReadyEvent extends BoardBridgeEvent {
  const BoardBridgeReadyEvent({this.rendererInstanceId = 'unity-board-1'});
  final String rendererInstanceId;
}

class BoardBridgeResyncRequestEvent extends BoardBridgeEvent {
  const BoardBridgeResyncRequestEvent({this.reason = 'RESYNC'});
  final String reason;
}

class BoardBridgeErrorEvent extends BoardBridgeEvent {
  const BoardBridgeErrorEvent({
    required this.code,
    required this.message,
    this.recoverable = true,
  });
  final String code;
  final String message;
  final bool recoverable;
}

abstract interface class BoardRenderer {
  bool get isAvailable;
  bool get isReady;
  bool get inputEnabled;
  BoardSnapshot? get currentSnapshot;
  Stream<BoardInteraction> get interactions;
  Stream<BoardBridgeEvent> get bridgeEvents;
  Future<void> attach(BoardSnapshot snapshot);
  Future<void> syncSnapshot(BoardSnapshot snapshot);
  Future<void> setInputEnabled(bool enabled);
  Future<void> render(GameSession game);
  Future<void> resetCamera();
  void detach();
  void dispose();
}

/// Replace with the versioned JSON adapter only after compatibility validation.
/// This preview neither reports native Unity availability nor fabricates moves,
/// while supporting the full bridge lifecycle for UI orchestration.
class PlaceholderUnityRenderer implements BoardRenderer {
  final _interactions = StreamController<BoardInteraction>.broadcast();
  final _bridgeEvents = StreamController<BoardBridgeEvent>.broadcast();
  GameSession? lastSnapshot;
  BoardSnapshot? _currentSnapshot;
  bool _ready = true;
  bool _inputEnabled = false;
  int attachmentCount = 0;

  @override
  bool get isAvailable => false;
  @override
  bool get isReady => _ready;
  @override
  bool get inputEnabled => _inputEnabled;
  @override
  BoardSnapshot? get currentSnapshot => _currentSnapshot;
  @override
  Stream<BoardInteraction> get interactions => _interactions.stream;
  @override
  Stream<BoardBridgeEvent> get bridgeEvents => _bridgeEvents.stream;

  @override
  Future<void> attach(BoardSnapshot snapshot) async {
    attachmentCount++;
    _ready = true;
    _currentSnapshot = snapshot;
    lastSnapshot = snapshot.game;
    _inputEnabled = snapshot.inputEnabled;
  }

  @override
  Future<void> syncSnapshot(BoardSnapshot snapshot) async {
    _currentSnapshot = snapshot;
    lastSnapshot = snapshot.game;
    _inputEnabled = snapshot.inputEnabled;
  }

  @override
  Future<void> setInputEnabled(bool enabled) async {
    _inputEnabled = enabled;
    final current = _currentSnapshot;
    if (current != null) {
      _currentSnapshot = BoardSnapshot(
        game: current.game,
        selectedSquare: current.selectedSquare,
        legalMoves: current.legalMoves,
        pendingPromotion: current.pendingPromotion,
        phase: current.phase,
        inputEnabled: enabled,
        cameraFlipped: current.cameraFlipped,
      );
    }
  }

  @override
  Future<void> render(GameSession game) async {
    lastSnapshot = game;
    final current = _currentSnapshot;
    _currentSnapshot = BoardSnapshot(
      game: game,
      selectedSquare: current?.selectedSquare,
      legalMoves: current?.legalMoves ?? const [],
      pendingPromotion: current?.pendingPromotion,
      phase: current?.phase ?? GamePhase.humanTurn,
      inputEnabled: _inputEnabled,
      cameraFlipped: game.humanColor == PlayerColor.black,
    );
  }

  @override
  Future<void> resetCamera() async {}

  @override
  void detach() {
    _inputEnabled = false;
  }

  @override
  void dispose() {
    unawaited(_interactions.close());
    unawaited(_bridgeEvents.close());
  }
}

/// Interface-based mock Unity bridge for developing and testing the Game screen
/// before the native Unity runtime is embedded.
class MockUnityBoardRenderer implements BoardRenderer {
  MockUnityBoardRenderer({
    this.autoReady = true,
    this.failOnAttach = false,
    this.failOnSync = false,
    this.failOnResetCamera = false,
  }) : _ready = autoReady && !failOnAttach;

  final bool autoReady;
  bool failOnAttach;
  bool failOnSync;
  bool failOnResetCamera;

  final _interactions = StreamController<BoardInteraction>.broadcast();
  final _bridgeEvents = StreamController<BoardBridgeEvent>.broadcast();

  Completer<void>? _pendingReadyCompleter;
  BoardSnapshot? _currentSnapshot;
  final List<BoardSnapshot> snapshotHistory = [];
  bool _ready;
  bool _inputEnabled = false;
  int attachmentCount = 0;
  int cameraResetCount = 0;

  @override
  bool get isAvailable => true;
  @override
  bool get isReady => _ready;
  @override
  bool get inputEnabled => _inputEnabled;
  @override
  BoardSnapshot? get currentSnapshot => _currentSnapshot;
  @override
  Stream<BoardInteraction> get interactions => _interactions.stream;
  @override
  Stream<BoardBridgeEvent> get bridgeEvents => _bridgeEvents.stream;

  @override
  Future<void> attach(BoardSnapshot snapshot) async {
    attachmentCount++;
    if (failOnAttach) {
      _ready = false;
      _inputEnabled = false;
      throw StateError('Unity scene failed to initialize.');
    }
    if (!autoReady) {
      _ready = false;
      _inputEnabled = false;
      _pendingReadyCompleter = Completer<void>();
      await _pendingReadyCompleter!.future;
    }
    _ready = true;
    _currentSnapshot = snapshot;
    _inputEnabled = snapshot.inputEnabled;
    snapshotHistory.add(snapshot);
  }

  void completeReady() {
    _ready = true;
    final completer = _pendingReadyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    if (!_bridgeEvents.isClosed) {
      _bridgeEvents.add(const BoardBridgeReadyEvent());
    }
  }

  void emitCommunicationError(
    String message, {
    String code = 'RENDER_FAILURE',
    bool recoverable = true,
  }) {
    _inputEnabled = false;
    if (!_bridgeEvents.isClosed) {
      _bridgeEvents.add(
        BoardBridgeErrorEvent(
          code: code,
          message: message,
          recoverable: recoverable,
        ),
      );
    }
  }

  void emitResyncRequest({String reason = 'RESYNC'}) {
    if (!_bridgeEvents.isClosed) {
      _bridgeEvents.add(BoardBridgeResyncRequestEvent(reason: reason));
    }
  }

  void simulateSquareTap(String square, {String? gameId, int? revision}) {
    final snapshot = _currentSnapshot;
    if (snapshot == null) return;
    if (!_interactions.isClosed) {
      _interactions.add(
        BoardInteraction(
          gameId: gameId ?? snapshot.gameId,
          revision: revision ?? snapshot.revision,
          square: square,
        ),
      );
    }
  }

  @override
  Future<void> syncSnapshot(BoardSnapshot snapshot) async {
    if (failOnSync) {
      throw StateError('Unity bridge message delivery failed.');
    }
    if (!_ready) return;
    _currentSnapshot = snapshot;
    _inputEnabled = snapshot.inputEnabled;
    snapshotHistory.add(snapshot);
  }

  @override
  Future<void> setInputEnabled(bool enabled) async {
    _inputEnabled = enabled;
    final current = _currentSnapshot;
    if (current != null) {
      final updated = BoardSnapshot(
        game: current.game,
        selectedSquare: current.selectedSquare,
        legalMoves: current.legalMoves,
        pendingPromotion: current.pendingPromotion,
        phase: current.phase,
        inputEnabled: enabled,
        cameraFlipped: current.cameraFlipped,
      );
      _currentSnapshot = updated;
      snapshotHistory.add(updated);
    }
  }

  @override
  Future<void> render(GameSession game) async {
    if (failOnSync) {
      throw StateError('Unity bridge render failed.');
    }
    final current = _currentSnapshot;
    final updated = BoardSnapshot(
      game: game,
      selectedSquare: current?.selectedSquare,
      legalMoves: current?.legalMoves ?? const [],
      pendingPromotion: current?.pendingPromotion,
      phase: current?.phase ?? GamePhase.humanTurn,
      inputEnabled: _inputEnabled,
      cameraFlipped: game.humanColor == PlayerColor.black,
    );
    _currentSnapshot = updated;
    snapshotHistory.add(updated);
  }

  @override
  Future<void> resetCamera() async {
    if (failOnResetCamera) {
      throw StateError('Camera reset failed.');
    }
    cameraResetCount++;
  }

  @override
  void detach() {
    _inputEnabled = false;
  }

  @override
  void dispose() {
    unawaited(_interactions.close());
    unawaited(_bridgeEvents.close());
  }
}
