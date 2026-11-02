import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../services/chess/chess_rules.dart';
import '../../../services/stockfish/chess_engine.dart';
import '../../../services/storage/local_storage.dart';
import '../../../services/unity/board_renderer.dart';
import '../domain/chess/chess_position.dart';
import '../domain/game_session.dart';

enum MoveActor { human, engine }

/// Canonical session orchestration. Widgets never write to native services.
class GameController extends ChangeNotifier {
  GameController({
    required this._repository,
    required this.rules,
    required this.engine,
    required this.renderer,
    Random? random,
  }) : _random = random ?? Random(),
       _boardReady = renderer.isReady {
    _interactionSubscription = renderer.interactions.listen(_onBoardInteraction);
    _bridgeEventSubscription = renderer.bridgeEvents.listen(_onBridgeEvent);
  }

  final GameRepository _repository;
  final ChessRules rules;
  final ChessEngine engine;
  final BoardRenderer renderer;
  final Random _random;

  StreamSubscription<BoardInteraction>? _interactionSubscription;
  StreamSubscription<BoardBridgeEvent>? _bridgeEventSubscription;

  List<GameSession> _games = const [];
  String? _activeId;
  bool _busy = false;
  bool _disposed = false;
  bool _boardReady;
  String? _boardError;
  bool _paused = false;
  bool _aiThinking = false;
  bool _applyingMove = false;
  String? _selectedSquare;
  List<String> _legalMovesForSelection = const [];
  PendingPromotion? _pendingPromotion;
  String? _error;
  int _nextId = 0;
  int _aiGeneration = 0;

  List<GameSession> get games => List.unmodifiable(_games);
  GameSession? get activeGame {
    final game = find(_activeId);
    return game != null && !game.isFinished ? game : null;
  }

  bool get busy => _busy;
  bool get isBoardReady => _boardReady;
  String? get boardError => _boardError;
  bool get isPaused => _paused;
  bool get isAiThinking => _aiThinking;
  bool get isApplyingMove => _applyingMove;
  String? get selectedSquare => _selectedSquare;
  List<String> get legalMovesForSelection =>
      List.unmodifiable(_legalMovesForSelection);
  PendingPromotion? get pendingPromotion => _pendingPromotion;
  String? get error => _error;
  bool get canPlay =>
      rules.isAvailable && engine.isAvailable && renderer.isAvailable;

  GamePhase phaseFor(GameSession? game) {
    if (!_boardReady && _boardError == null) return GamePhase.loading;
    if (_boardError != null) return GamePhase.recoverableError;
    if (game == null || game.isFinished) return GamePhase.finished;
    if (_paused) return GamePhase.paused;
    if (_pendingPromotion != null && _pendingPromotion!.gameId == game.id) {
      return GamePhase.promotionPending;
    }
    if (_applyingMove) return GamePhase.applyingMove;
    if (_aiThinking) return GamePhase.aiThinking;
    return GamePhase.humanTurn;
  }

  bool isPlayerInputEnabledFor(GameSession? game) {
    if (game == null || game.isFinished) return false;
    if (!_boardReady || _boardError != null) return false;
    if (_busy || _applyingMove || _aiThinking || _paused) return false;
    if (_pendingPromotion != null) return false;
    return game.isHumanTurn;
  }

  BoardSnapshot buildSnapshot(GameSession game) {
    final promotion =
        _pendingPromotion != null && _pendingPromotion!.gameId == game.id
            ? _pendingPromotion
            : null;
    return BoardSnapshot(
      game: game,
      selectedSquare: _selectedSquare,
      legalMoves: _legalMovesForSelection,
      pendingPromotion: promotion,
      phase: phaseFor(game),
      inputEnabled: isPlayerInputEnabledFor(game),
      cameraFlipped: game.humanColor == PlayerColor.black,
    );
  }

  GameSession? find(String? id) {
    for (final game in _games) {
      if (game.id == id) return game;
    }
    return null;
  }

  List<String> legalDestinations(String gameId, String square) {
    final game = find(gameId);
    if (game == null || game.isFinished || !rules.isAvailable) return const [];
    return rules.legalDestinations(game, square);
  }

  String? exportPgn(String gameId) {
    final game = find(gameId);
    if (game == null) return null;
    return rules.exportPgn(game);
  }

  Future<void> load() async {
    _games = await _repository.loadGames();
    _activeId = null;
    for (final game in _games) {
      if (!game.isFinished) {
        _activeId = game.id;
        break;
      }
    }
  }

  Future<GameSession?> start(GameConfiguration configuration) async {
    if (_busy || _disposed) return null;
    _busy = true;
    _error = null;
    _boardError = null;
    _paused = false;
    _aiThinking = false;
    _applyingMove = false;
    _selectedSquare = null;
    _legalMovesForSelection = const [];
    _pendingPromotion = null;
    _aiGeneration++;
    notifyListeners();
    try {
      final resolvedConfiguration = configuration.resolve(_random);
      final now = DateTime.now();
      final game = GameSession(
        id: '${now.microsecondsSinceEpoch}-${_nextId++}',
        configuration: resolvedConfiguration,
        startedAt: now,
      );
      await _repository.saveGame(game);
      if (_disposed) return null;
      _games = [game, ..._games];
      _activeId = game.id;
      // A renderer failure must not undo a successfully persisted session.
      try {
        await renderer.render(game);
      } catch (_) {
        _boardError =
            'The board could not be opened. Your session is still available.';
        _error = _boardError;
      }
      return _disposed ? null : game;
    } catch (_) {
      _error = 'The session could not be created. Please try again.';
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Attaches or recreates the Unity board view and restores the full board state.
  Future<void> attachBoard(String gameId) async {
    if (_disposed) return;
    final game = find(gameId);
    if (game == null) return;
    _boardError = null;
    _error = null;
    _boardReady = renderer.isReady;
    await Future<void>.value();
    if (_disposed) return;
    if (!_boardReady) {
      notifyListeners();
    }
    try {
      await renderer.attach(buildSnapshot(game));
      if (_disposed) return;
      _boardReady = renderer.isReady;
      final latest = find(gameId) ?? game;
      await renderer.syncSnapshot(buildSnapshot(latest));
      if (!_disposed) notifyListeners();
      if (!latest.isFinished &&
          latest.isAiTurn &&
          !_paused &&
          !_aiThinking &&
          engine.isAvailable &&
          rules.isAvailable) {
        unawaited(_runAiTurn(latest));
      }
    } catch (_) {
      if (_disposed) return;
      _boardReady = false;
      _boardError =
          'The 3D board could not be initialized. Please retry the board connection.';
      _error = _boardError;
      await _safeDisableInput();
      notifyListeners();
    }
  }

  Future<void> onSquareTapped(String gameId, String square) async {
    final game = find(gameId);
    if (!isPlayerInputEnabledFor(game) || game == null) return;

    if (_selectedSquare != null) {
      final matchingMoves = _legalMovesForSelection
          .where((uci) => _destinationSquare(uci) == square)
          .toList();
      if (matchingMoves.isNotEmpty) {
        final promotionMoves =
            matchingMoves.where((uci) => uci.length == 5).toList();
        if (promotionMoves.isNotEmpty) {
          requestPromotion(
            gameId: game.id,
            from: _selectedSquare!,
            to: square,
          );
          return;
        }
        await attemptMove(
          game.id,
          matchingMoves.first,
          expectedRevision: game.revision,
          actor: MoveActor.human,
        );
        return;
      }
    }

    if (_selectedSquare == square) {
      _selectedSquare = null;
      _legalMovesForSelection = const [];
    } else if (rules.isAvailable) {
      final moves = rules.legalMoves(game, square);
      if (moves.isNotEmpty) {
        _selectedSquare = square;
        _legalMovesForSelection = moves;
      } else {
        _selectedSquare = null;
        _legalMovesForSelection = const [];
      }
    } else {
      _selectedSquare = square;
      _legalMovesForSelection = const [];
    }

    await _syncRenderer(game);
    if (!_disposed) notifyListeners();
  }

  void requestPromotion({
    required String gameId,
    required String from,
    required String to,
    List<PromotionPiece> choices = PromotionPiece.values,
  }) {
    final game = find(gameId);
    if (game == null || game.isFinished || _disposed) return;
    if (_applyingMove || _aiThinking || _paused) return;
    _pendingPromotion = PendingPromotion(
      gameId: game.id,
      revision: game.revision,
      from: from,
      to: to,
      color: game.humanColor,
      choices: choices,
    );
    unawaited(_syncRenderer(game));
    notifyListeners();
  }

  Future<GameSession?> selectPromotion(PromotionPiece piece) async {
    final pending = _pendingPromotion;
    if (pending == null || _disposed || _busy || _applyingMove) return null;
    if (!pending.choices.contains(piece)) return null;
    final uci = '${pending.from}${pending.to}${piece.uciCode}';
    _pendingPromotion = null;
    return attemptMove(
      pending.gameId,
      uci,
      expectedRevision: pending.revision,
      actor: MoveActor.human,
    );
  }

  Future<void> cancelPromotion() async {
    final pending = _pendingPromotion;
    if (pending == null || _disposed) return;
    _pendingPromotion = null;
    _selectedSquare = null;
    _legalMovesForSelection = const [];
    final game = find(pending.gameId);
    if (game != null) {
      await _syncRenderer(game);
    }
    if (!_disposed) notifyListeners();
  }

  Future<GameSession?> attemptMove(
    String gameId,
    String uci, {
    int? expectedRevision,
    MoveActor actor = MoveActor.human,
  }) async {
    final current = find(gameId);
    if (current == null || current.isFinished || _disposed) return null;
    if (_busy || _applyingMove || _paused) return null;
    if (actor == MoveActor.human && _aiThinking) return null;
    if (!_boardReady || _boardError != null) return null;
    if (expectedRevision != null && current.revision != expectedRevision) {
      return null;
    }
    final expectedActor =
        current.isHumanTurn ? MoveActor.human : MoveActor.engine;
    if (actor != expectedActor) return null;

    _busy = true;
    _applyingMove = true;
    _error = null;
    _selectedSquare = null;
    _legalMovesForSelection = const [];
    _pendingPromotion = null;
    unawaited(_safeDisableInput());
    if (!_disposed) notifyListeners();

    try {
      final updated = rules.applyMove(current, uci);
      await _repository.saveGame(updated);
      if (_disposed) return null;
      _games = [
        for (final game in _games)
          if (game.id == gameId) updated else game,
      ];
      if (updated.isFinished && _activeId == gameId) {
        _activeId = null;
      }
      _busy = false;
      _applyingMove = false;
      try {
        await renderer.render(updated);
        await renderer.syncSnapshot(buildSnapshot(updated));
      } catch (_) {
        _boardError =
            'Board communication was interrupted. Retry to restore the 3D view.';
        _error = _boardError;
        await _safeDisableInput();
      }
      if (!_disposed) notifyListeners();

      if (actor == MoveActor.human &&
          !updated.isFinished &&
          updated.isAiTurn &&
          !_paused &&
          engine.isAvailable &&
          rules.isAvailable) {
        await _runAiTurn(updated);
      }
      return find(gameId) ?? updated;
    } catch (_) {
      _busy = false;
      _applyingMove = false;
      _error = 'That move could not be applied. Please try again.';
      if (!_disposed) notifyListeners();
      return null;
    }
  }

  Future<GameSession?> undo(
    String gameId, {
    int? expectedRevision,
    int plies = 1,
  }) async {
    final current = find(gameId);
    if (current == null || _busy || _applyingMove || _disposed) return null;
    if (expectedRevision != null && current.revision != expectedRevision) {
      return null;
    }
    _busy = true;
    _error = null;
    _aiGeneration++;
    notifyListeners();
    try {
      if (_aiThinking) {
        _aiThinking = false;
        await engine.cancel();
      }
      _selectedSquare = null;
      _legalMovesForSelection = const [];
      _pendingPromotion = null;
      final updated = rules.undo(current, plies: plies);
      await _repository.saveGame(updated);
      if (_disposed) return null;
      _games = [
        for (final game in _games)
          if (game.id == gameId) updated else game,
      ];
      _activeId = updated.isFinished ? null : updated.id;
      try {
        await renderer.render(updated);
        await renderer.syncSnapshot(buildSnapshot(updated));
      } catch (_) {}
      return updated;
    } catch (_) {
      _error = 'The move could not be undone.';
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<GameSession?> claimDraw(
    String gameId,
    DrawClaim claim, {
    int? expectedRevision,
    MoveActor actor = MoveActor.human,
    String? intendedMove,
  }) async {
    final current = find(gameId);
    if (current == null ||
        current.isFinished ||
        _busy ||
        _applyingMove ||
        _disposed) {
      return null;
    }
    if (expectedRevision != null && current.revision != expectedRevision) {
      return null;
    }
    final expectedActor =
        current.isHumanTurn ? MoveActor.human : MoveActor.engine;
    if (actor != expectedActor) return null;

    _busy = true;
    _error = null;
    _aiGeneration++;
    notifyListeners();
    try {
      final claimed = rules.claimDraw(
        current,
        claim,
        intendedMove: intendedMove,
      );
      await _repository.saveGame(claimed);
      if (_disposed) return null;
      _games = [
        for (final game in _games)
          if (game.id == gameId) claimed else game,
      ];
      if (_activeId == gameId) _activeId = null;
      try {
        await renderer.render(claimed);
        await renderer.syncSnapshot(buildSnapshot(claimed));
      } catch (_) {}
      return claimed;
    } catch (_) {
      _error = 'The draw claim could not be completed.';
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _runAiTurn(GameSession game) async {
    if (_disposed || game.isFinished || _paused || _aiThinking) return;
    final generation = ++_aiGeneration;
    _aiThinking = true;
    _error = null;
    await _syncRenderer(game);
    if (!_disposed) notifyListeners();

    try {
      final aiUci = await engine.search(game);
      if (_disposed || generation != _aiGeneration || _paused) return;
      final latest = find(game.id);
      if (latest == null ||
          latest.isFinished ||
          latest.revision != game.revision) {
        return;
      }
      _aiThinking = false;
      await attemptMove(
        latest.id,
        aiUci,
        expectedRevision: latest.revision,
        actor: MoveActor.engine,
      );
    } catch (_) {
      if (_disposed || generation != _aiGeneration) return;
      _aiThinking = false;
      _applyingMove = false;
      _error = 'The AI opponent could not complete its move. You can retry.';
      final latest = find(game.id);
      if (latest != null) {
        await _syncRenderer(latest);
      }
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> retryAiMove(String gameId) async {
    final game = find(gameId);
    if (game == null || game.isFinished || !game.isAiTurn) return;
    if (_busy || _applyingMove || _aiThinking || _paused) return;
    if (!engine.isAvailable || !rules.isAvailable) return;
    await _runAiTurn(game);
  }

  Future<void> pauseGame(String id) async {
    final current = find(id);
    if (current == null || current.isFinished || _paused || _disposed) return;
    _paused = true;
    _aiGeneration++;
    if (_aiThinking) {
      _aiThinking = false;
      await engine.cancel();
    }
    await _syncRenderer(current);
    if (!_disposed) notifyListeners();
  }

  Future<void> resumeGame(String id) async {
    final current = find(id);
    if (current == null || current.isFinished || !_paused || _disposed) return;
    _paused = false;
    await _syncRenderer(current);
    if (!_disposed) notifyListeners();
    if (current.isAiTurn && engine.isAvailable && rules.isAvailable) {
      unawaited(_runAiTurn(current));
    }
  }

  Future<GameSession?> restart(String id) async {
    final current = find(id);
    if (_busy || _disposed || current == null) return null;
    _busy = true;
    _error = null;
    _boardError = null;
    _aiGeneration++;
    notifyListeners();
    try {
      await engine.cancel();
      _paused = false;
      _aiThinking = false;
      _applyingMove = false;
      _selectedSquare = null;
      _legalMovesForSelection = const [];
      _pendingPromotion = null;
      final restarted = current.restart(DateTime.now());
      await _repository.saveGame(restarted);
      if (_disposed) return null;
      _games = [
        for (final game in _games)
          if (game.id == id) restarted else game,
      ];
      _activeId = restarted.id;
      await renderer.render(restarted);
      await _syncRenderer(restarted);
      if (!restarted.isFinished &&
          restarted.isAiTurn &&
          engine.isAvailable &&
          rules.isAvailable) {
        unawaited(_runAiTurn(restarted));
      }
      return restarted;
    } catch (_) {
      _error = 'The game could not be restarted. Please try again.';
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<GameSession?> resign(String id) async {
    final current = find(id);
    if (_busy || _disposed || current == null || current.isFinished) {
      return null;
    }
    _busy = true;
    _error = null;
    _aiGeneration++;
    notifyListeners();
    try {
      _paused = false;
      _aiThinking = false;
      _applyingMove = false;
      _selectedSquare = null;
      _legalMovesForSelection = const [];
      _pendingPromotion = null;
      await engine.cancel();
      final finished = current.resign(DateTime.now());
      await _repository.saveGame(finished);
      if (_disposed) return null;
      _games = [
        for (final game in _games)
          if (game.id == id) finished else game,
      ];
      if (_activeId == id) _activeId = null;
      await renderer.render(finished);
      await _syncRenderer(finished);
      return finished;
    } catch (_) {
      _error = 'The result could not be saved. Please try again.';
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resetCamera() async {
    try {
      _error = null;
      await renderer.resetCamera();
      if (!_disposed) notifyListeners();
    } catch (_) {
      _error = 'The camera could not be reset.';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _syncRenderer(GameSession game) async {
    try {
      await renderer.syncSnapshot(buildSnapshot(game));
    } catch (_) {
      _boardError =
          'Board communication was interrupted. Retry to restore the 3D view.';
      _error = _boardError;
      await _safeDisableInput();
    }
  }

  Future<void> _safeDisableInput() async {
    try {
      await renderer.setInputEnabled(false);
    } catch (_) {}
  }

  void _onBoardInteraction(BoardInteraction interaction) {
    if (_disposed) return;
    final game = find(interaction.gameId);
    if (game == null || game.revision != interaction.revision) return;
    if (!isPlayerInputEnabledFor(game)) return;
    unawaited(onSquareTapped(game.id, interaction.square));
  }

  void _onBridgeEvent(BoardBridgeEvent event) {
    if (_disposed) return;
    final active = activeGame ?? (_games.isNotEmpty ? _games.first : null);
    switch (event) {
      case BoardBridgeReadyEvent():
        _boardReady = true;
        _boardError = null;
        _error = null;
        if (active != null) {
          unawaited(_syncRenderer(active));
        }
        notifyListeners();
      case BoardBridgeResyncRequestEvent():
        if (active != null) {
          unawaited(_syncRenderer(active));
        }
        notifyListeners();
      case BoardBridgeErrorEvent():
        _boardError = event.message;
        _error = event.message;
        unawaited(_safeDisableInput());
        notifyListeners();
    }
  }

  static String _destinationSquare(String uci) =>
      uci.length >= 4 ? uci.substring(2, 4) : uci;

  @override
  void dispose() {
    _disposed = true;
    _aiGeneration++;
    unawaited(_interactionSubscription?.cancel());
    unawaited(_bridgeEventSubscription?.cancel());
    super.dispose();
  }
}
